using Microsoft.Data.SqlClient;
using System;
using System.Collections.Concurrent;
using System.Data;
using System.Data.Common;
using System.IO;
using System.Linq;
using System.Net;
using System.Threading;
using System.Threading.Tasks;

namespace SqlFailoverTest
{
    internal class SqlDnsTest
    {
        public void Run()
        {
            // ServicePointManager.EnableDnsRoundRobin = true;
            // ServicePointManager.DnsRefreshTimeout = 10 * 1000;

            var cts = new CancellationTokenSource();
            Console.CancelKeyPress += (sender, args) =>
            {
                cts.Cancel();
            };

            Console.WriteLine($"RefreshDNS = {RefreshDNS}");
            Console.WriteLine($"SqlConnectionStringFile = {SqlConnectionStringFile}");
            Console.WriteLine($"SqlConnectionStringList = {string.Join(" | ", SqlConnectionStringList)}");
            Console.WriteLine($"EnableDnsRoundRobin = {ServicePointManager.EnableDnsRoundRobin}");
            Console.WriteLine($"DnsRefreshTimeout = {ServicePointManager.DnsRefreshTimeout}");

            while (!cts.IsCancellationRequested)
            {
                bool isDNSRefreshed = false;
                foreach (var sqlConnectionString in SqlConnectionStringList)
                {
                    isDNSRefreshed |= DNSRefresh(sqlConnectionString);
                }

                if (isDNSRefreshed && RefreshDNS)
                {
                    SqlConnection.ClearAllPools();
                    WriteLog($"RefreshDBConnections: ClearAllPools");
                }

                var rwQuery = "update TestTable1 set col2=GETUTCDATE() where col1=1;";
                var roQuery = "select top 1 * from TestTable1 where col1=1;";

                RunQuery("RW", SqlConnectionStringList[0], rwQuery);
                RunQuery("RO", SqlConnectionStringList[1], roQuery);

                Thread.Sleep(10000);
            }
        }

        private static void RunQuery(string tag, string connectionString, string query)
        {
            try
            {
                using (var sqlConnection = new SqlConnection(connectionString))
                {
                    try
                    {
                        sqlConnection.Open();
                        using (var sqlCommand = new SqlCommand(query, sqlConnection))
                        {
                            sqlCommand.ExecuteNonQuery();
                        }
                    }
                    catch (SqlException sqlEx)
                    {
                        HandleExceptionForResiliency(sqlEx, sqlConnection);
                    }
                }
            }
            catch (Exception ex)
            {
                var hostName = new SqlConnectionStringBuilder(connectionString).DataSource.Split(':').Last();//remove prefix tcp: if any
                var exMessage = ex.ToString().Replace(Environment.NewLine, " #N# ");
                if (exMessage.Contains("because the database is read-only.")) { exMessage = "read-only error !!!!!!!!!!!!!!!!!!!!"; }
                else if (exMessage.Contains("No such host is known")) { exMessage = "NoHostKnown error !!!!!!!!!!!!!!!!!!!!"; }

                WriteLog($"RefreshDBConnections: exQry-{tag}, {hostName}, {exMessage}");
            }
        }

        private const int SqlReadOnlyErrorNumber = 3906;

        /// <summary>
        /// Helper method to look at a SQL Exception and take actions to improve resiliency for the process.
        /// e.g. If the exception error was a read only exception (BCP flip scenario) clear the connection pool.
        /// </summary>
        /// <param name="ex">The sql exception that was caught.</param>
        public static void HandleExceptionForResiliency(DbException ex, DbConnection connection)
        {
            if (ex.GetNumber() == SqlReadOnlyErrorNumber)
            {
                WriteLog("HandleExceptionForResiliency - ClearPool");
                connection.ClearPool();
                if (connection != null && connection.State != ConnectionState.Closed)
                {
                    WriteLog("HandleExceptionForResiliency - CloseConnection");
                    connection.Close();
                }
            }
        }

        private static bool RefreshDNS => bool.TryParse(Environment.GetEnvironmentVariable("RefreshDNS"), out var refreshDNS) && refreshDNS;

        private static string SqlConnectionStringFile => Environment.GetEnvironmentVariable("SqlConnectionStringFile") ?? "connections.txt";
        private static string[] SqlConnectionStringList => (File.ReadAllText(SqlConnectionStringFile)?.Trim() ?? throw new InvalidOperationException("invalid connection string / file provided by SqlConnectionStringFile env variable")).Split(Environment.NewLine, StringSplitOptions.RemoveEmptyEntries);

        private ConcurrentDictionary<string, string> HostNameToAliasIp = new ConcurrentDictionary<string, string>();

        private static void WriteLog(string message) => Console.WriteLine($"[{DateTime.UtcNow.ToString("o")}] {message}");

        internal bool DNSRefresh(string connectionString)
        {
            var isDNSRefreshed = false;
            string hostName = string.Empty;
            try
            {
                var dbConnection = new SqlConnection(connectionString);
                hostName = dbConnection.DataSource.Split(':').Last();//remove prefix tcp: if any
                var entry = GetHostEntryAsync(hostName).Result;
                var newAddressIP = string.Join("|", entry.AddressList.Select(a => a.ToString()));
                HostNameToAliasIp.AddOrUpdate(
                    hostName,
                    addValueFactory: _ =>
                    {
                        WriteLog($"RefreshDBConnections: newConct, {hostName}, {newAddressIP}");
                        return newAddressIP;
                    },
                    updateValueFactory: (_, oldAddressIp) =>
                    {
                        if (!oldAddressIp.Equals(newAddressIP))
                        {
                            isDNSRefreshed = true;
                            WriteLog($"RefreshDBConnections: failover, {hostName}, {newAddressIP}, x{oldAddressIp}");
                        }

                        return newAddressIP;
                    });
            }
            catch (Exception ex)
            {
                WriteLog($"RefreshDBConnections: exDnsRef, {hostName}, {ex.ToString().Replace(Environment.NewLine, " #N# ")}");
            }

            return isDNSRefreshed;
        }

        internal virtual async Task<IPHostEntry> GetHostEntryAsync(string hostName)
        {
            return await Dns.GetHostEntryAsync(hostName).ConfigureAwait(false);
        }
    }

    internal static class DbExceptionExtensions
    {
        public static int GetNumber(this DbException ex)
        {
            if (ex is System.Data.SqlClient.SqlException ex1) { return ex1.Number; }
            else if (ex is Microsoft.Data.SqlClient.SqlException ex2) { return ex2.Number; }
            else throw new NotSupportedException();
        }

        public static void ClearPool(this DbConnection dbConnection)
        {
            if (dbConnection is System.Data.SqlClient.SqlConnection dbConnection1) { System.Data.SqlClient.SqlConnection.ClearPool(dbConnection1); }
            else if (dbConnection is Microsoft.Data.SqlClient.SqlConnection dbConnection2) { Microsoft.Data.SqlClient.SqlConnection.ClearPool(dbConnection2); }
            else throw new NotSupportedException();
        }
    }
}
