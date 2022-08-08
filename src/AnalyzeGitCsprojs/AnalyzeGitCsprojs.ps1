if(!$env:INETROOT) { throw 'INETROOT env variable undefined. Run this script in powershell started from enlistment.' }
$result = Get-ChildItem -Path "$env:INETROOT\private" -Filter *.csproj -Recurse | %{ 
  try { [xml]$content = Get-Content -Raw -LiteralPath $_.FullName; } catch { write-warning "invalid parse of $($_.FullName)" } 
  $isSDK=$false; 
  if($content.Project.Sdk) { $isSDK=$true; } 
  $frameworkVersion = $content.Project.PropertyGroup.TargetFramework | where { ![string]::IsNullOrWhiteSpace($_) } | select -First 1; 
  if(!$frameworkVersion) { $frameworkVersion = $content.Project.PropertyGroup.TargetFrameworkVersion | where { ![string]::IsNullOrWhiteSpace($_) } | select -First 1; } 
  if(!$frameworkVersion) { $frameworkVersion = $content.Project.PropertyGroup.TargetFrameworks | where { ![string]::IsNullOrWhiteSpace($_) } | select -First 1; } 
  if(!$frameworkVersion) {
    $rawXmlContent = $content.OuterXml; 
    $fetchFromRedirectProps = $false;
    if($rawXmlContent.Contains('xunit.qtest.props')) { $fetchFromRedirectProps=$true; }
    if(!$frameworkVersion -and $rawXmlContent.Contains('netcore.runtime.props')) { $fetchFromRedirectProps=$true; }
    if(!$frameworkVersion -and $rawXmlContent.Contains('xunit.cloudtest.props')) { $fetchFromRedirectProps=$true; }
    if(!$frameworkVersion -and $rawXmlContent.Contains('azure.functions.props')) { $fetchFromRedirectProps=$true; }
    if(!$frameworkVersion -and $rawXmlContent.Contains('netcore.props')) { $fetchFromRedirectProps=$true; }
    if($fetchFromRedirectProps) {
      $redirectProps = "$env:INETROOT\private\vNEXT\devops\build\netcore.props";
      [xml]$content = Get-Content -Raw -LiteralPath $redirectProps;
      $frameworkVersion = $content.Project.PropertyGroup.TargetFramework | where { ![string]::IsNullOrWhiteSpace($_) } | select -First 1; 
    }
  }
  return New-Object PSObject -Property @{ 
    FullPath=$($_.FullName.Replace($env:INETROOT,'').Trim('/').Trim('\')); 
    isSDK=$isSDK; 
    frameworkVersion=$frameworkVersion; }; 
}
