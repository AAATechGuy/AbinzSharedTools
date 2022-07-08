using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;
using System.Reflection;

namespace SqlFailoverTest
{
    internal class Program
    {
        static void Main(string[] args)
        {
            Console.WriteLine("start");
            new SqlDnsTest().Run();
            Console.WriteLine("done");
        }
    }
}
