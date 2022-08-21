namespace External;

public class ExternalLogic
{
    public static CampaignType Method1(ImportCampaign ic, Campaign c, bool isLocalorBulkFormatLocalImport, ImportType importType)
    {
        return ic.Type != null && c != null && c.CampaignType == CampaignType.Search &&
            ic.Type == ImportCampaignType.DynamicSearchAds && c.ServerId != null
                ? (CampaignType)(byte)ic.Type
                : (isLocalorBulkFormatLocalImport || importType == ImportType.UpgradeServerImport) && c != null
                    ? c.ServerId == null && ic.Type != null
                        ? (CampaignType)(byte)ic.Type
                        : c.CampaignType
                    : (CampaignType)(byte)(ic.Type ?? ImportCampaignType.Search);
    }

    public static CampaignType Method2(ImportCampaign ic, Campaign c, bool isLocalorBulkFormatLocalImport, ImportType importType)
    {
        return ic.Type != null && c != null && //c.CampaignType == CampaignType.Search &&
            ic.Type == ImportCampaignType.DynamicSearchAds && c.ServerId != null
                ? (CampaignType)(byte)ic.Type
                : (isLocalorBulkFormatLocalImport || importType == ImportType.UpgradeServerImport) && c != null
                    ? c.ServerId == null && ic.Type != null
                        ? (CampaignType)(byte)ic.Type
                        : c.CampaignType
                    : (CampaignType)(byte)(ic.Type ?? ImportCampaignType.Search);
    }
}

#region ObjectModel

public enum CampaignType
{
    Shopping = 1,
    DynamicSearchAds = 2,
    Search = 3,
    Audience = 4,
    SmartShopping = 5,
    AudienceShopping = 6
}

public enum ImportCampaignType
{
    SearchAndContent = 0,
    Shopping = 1,
    DynamicSearchAds = 2,
    Search = 3,
    Audience = 4,
    SmartShopping = 5,
    AudienceShopping = 6
}

public enum ImportType
{
    LocalImport = 0,
    GetChanges = 1,
    GetChangesAfterPost = 2,
    UpgradeServerImport = 3,
    GetFullAccountDownload = 4,
    LocalImportBulkFormat = 5
}

public class ImportCampaign
{
    public ImportCampaignType? Type { get; set; }
}

public class Campaign
{
    public long? ServerId { get; set; }
    public CampaignType CampaignType { get; set; }
}

#endregion ObjectModel
