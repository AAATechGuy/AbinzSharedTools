using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;

namespace ConsoleApplication
{
    class Program
    {
        static void Main()
        {
            Action copyAction_60ms = new Action(() =>
            {
                LogInfo("task-begin");
                Thread.Sleep(60); // sleep for 60ms
                LogInfo("task-end");
            });

            Action copyAction_1060ms = new Action(() =>
            {
                LogInfo("task-begin");
                Thread.Sleep(1060);
                LogInfo("task-end");
            });

            Action copyAction_exAfter60ms = new Action(() =>
            {
                LogInfo("task-begin");
                Thread.Sleep(60); // sleep for 60ms
                throw new ApplicationException();
            });

            var cts = new CancellationTokenSource();

            Execute(() => WriteToStream(cts.Token, copyAction_60ms));
            Execute(() => WriteToStream2(cts.Token, copyAction_60ms));

            Execute(() => WriteToStream(cts.Token, copyAction_1060ms));
            Execute(() => WriteToStream2(cts.Token, copyAction_1060ms));

            Execute(() => WriteToStream(cts.Token, copyAction_exAfter60ms));
            Execute(() => WriteToStream2(cts.Token, copyAction_exAfter60ms));

            var ctsTimeoutAfter100ms = new CancellationTokenSource(100);
            Execute(() => WriteToStream(ctsTimeoutAfter100ms.Token, copyAction_1060ms));
            ctsTimeoutAfter100ms = new CancellationTokenSource(100);
            Execute(() => WriteToStream2(ctsTimeoutAfter100ms.Token, copyAction_1060ms));

            Console.ReadKey();
        }

        private static void Execute(Action action)
        {
            Console.WriteLine();
            LogInfo($"*** Execute.start");
            var stopwatch = Stopwatch.StartNew();
            try
            {
                action.Invoke();
            }
            catch (Exception ex)
            {
                LogInfo($"ex={ex.GetType().Name}; {ex.Message}");
            }
            LogInfo($"*** Execute.complete : elapsed {stopwatch.ElapsedMilliseconds} ms");
            Console.WriteLine();
        }

        internal static void WriteToStream2(CancellationToken cancellationToken, Action copyAction)
        {
            var copyTask = Task.Factory.StartNew(() => copyAction.Invoke());

            try
            {
                while (!copyTask.Wait(1000, cancellationToken))
                {
                    LogInfo(".");
                }

                if (copyTask.IsCompleted)
                {
                    LogInfo("Completed");
                }
            }
            catch (AggregateException)
            {
                LogInfo("AggregateException");
            }
            catch (OperationCanceledException)
            {
                LogInfo("OperationCanceledException");
            }
        }

        internal static void WriteToStream(CancellationToken cancellationToken, Action copyAction)
        {
            var copyTask = Task.Factory.StartNew(() => copyAction.Invoke());

            try
            {
                do
                {
                    LogInfo(".");

                    Task.Delay(1000).Wait(cancellationToken);
                }
                while (!copyTask.IsCompleted && !cancellationToken.IsCancellationRequested);

                if (copyTask.IsCompleted)
                {
                    LogInfo("Completed");
                }
            }
            catch (OperationCanceledException)
            {
                LogInfo("OperationCanceledException");
            }
        }

        private static void LogInfo(string message) => Console.WriteLine($"[{DateTime.UtcNow.ToString("HH:mm:ss.fff")}] {message}");
    }
}
