using Bogus;
using External;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Linq;

namespace ABTests;

[TestClass]
public class Tests
{
    [TestMethod]
    public void TestMethod1()
    {
        int failedCount = 0;
        foreach (var input in GetTestObjects(maxObjectsToGenerate: 1000))
        {
            var abTestResult = ObjectABTester.RunABTest<MethodParam, CampaignType>(
                input.MethodInput,
                methodParam => ExternalLogic.Method1(methodParam.ic, methodParam.c, methodParam.isLocalorBulkFormatLocalImport, methodParam.importType),
                methodParam => ExternalLogic.Method2(methodParam.ic, methodParam.c, methodParam.isLocalorBulkFormatLocalImport, methodParam.importType),
                resultComparer: (resultA, resultB) => resultA == resultB,
                exComparer: (exA, exB) => exA?.GetType() == exB?.GetType() && exA?.Message == exB?.Message);

            if (abTestResult != null)
            {
                Console.WriteLine($"[{DateTime.UtcNow.ToString("u")}][#{input.IterationId}] {abTestResult.MismatchType}: {JsonConvert.SerializeObject(input.MethodInput, Formatting.Indented)}");
                ++failedCount;
            }

            if (input.IterationId % 100 == 0)
            {
                Console.WriteLine($"[{DateTime.UtcNow.ToString("u")}][#{input.IterationId}] ..");
            }
        }

        if (failedCount > 0)
        {
            Assert.Fail($"failedCount={failedCount}");
        }
    }

    private static IEnumerable<(int IterationId, MethodParam MethodInput)> GetTestObjects(int maxObjectsToGenerate)
    {
        //Set the randomizer seed if you wish to generate repeatable data sets.
        Randomizer.Seed = new Random(8675309);

        var testImportCampaignsGen = new Faker<ImportCampaign>()
            .RuleFor(ic => ic.Type, f => f.PickRandom<ImportCampaignType>().OrNull(f, 0.8f));
        var testCampaignsGen = new Faker<Campaign>()
            .RuleFor(c => c.ServerId, f => f.Random.Long(-1, 2))
            .RuleFor(ic => ic.CampaignType, f => f.PickRandom<CampaignType>());
        var testMethodParamsGen = new Faker<MethodParam>()
            .RuleFor(p => p.ic, f => testImportCampaignsGen.Generate())
            .RuleFor(p => p.c, f => testCampaignsGen.Generate())
            .RuleFor(p => p.isLocalorBulkFormatLocalImport, f => f.Random.Bool())
            .RuleFor(p => p.importType, f => f.PickRandom<ImportType>());

        return Enumerable.Range(0, maxObjectsToGenerate)
            .Select(iterationId => (iterationId, testMethodParamsGen.Generate()));
    }

    public class MethodParam
    {
        public ImportCampaign ic;
        public Campaign c;
        public bool isLocalorBulkFormatLocalImport;
        public ImportType importType;
    }
}
