param(
  [Parameter(Mandatory=$true)][string]$TenantId,
  [Parameter(Mandatory=$true)][string]$ClientId,
  [Parameter(Mandatory=$true)][string]$ClientSecret,
  [Parameter(Mandatory=$true)][string]$ProdCsvPath,
  [Parameter(Mandatory=$true)][string]$NonProdCsvPath,
  [string]$OutputDir = "",
  [string]$BranchName = ""
)

$ErrorActionPreference='Stop'
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop

function Ensure-Dir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ $p = Join-Path (Get-Location) 'rg-perms-out' } if(-not(Test-Path $p)){ New-Item -ItemType Directory -Path $p -Force | Out-Null } return $p }
function Normalize([string]$s){ ($s -replace '[_\s]','').ToLowerInvariant() }
function Load-Expected($p){
  if(-not (Test-Path $p)){ throw "CSV not found: $p" }
  $raw = Import-Csv $p
  if(-not $raw){ throw "CSV empty: $p" }
  $map=@{}; foreach($h in $raw[0].psobject.Properties.Name){ $map[(Normalize $h)]=$h }
  foreach($need in 'resourcegroupname','roledefinitionname','adgroupname'){ if(-not $map.ContainsKey($need)){ throw "CSV '$p' missing col like '$need'" } }
  $rows=@(); foreach($r in $raw){ $rows += [pscustomobject]@{ RG="$($r.$($map['resourcegroupname']))".Trim(); Role="$($r.$($map['roledefinitionname']))".Trim(); AAD="$($r.$($map['adgroupname']))".Trim() } }
  $rows
}
function Get-EnvFromSub([string]$n){ if($n -match '(?i)\b(prod|prd|production)\b'){ 'PRODUCTION' } else { 'NONPRODUCTION' } }
function CustodianFromSub([string]$n){ if($n -match '(?i)ADH([A-Za-z0-9_-]+)'){ return $Matches[1] } return $null }
function Resolve-Group([string]$name){
  if([string]::IsNullOrWhiteSpace($name)){ return $null }
  $g = Get-AzADGroup -DisplayName $name -ErrorAction SilentlyContinue
  if(-not $g){ $g = Get-AzADGroup -SearchString $name -ErrorAction SilentlyContinue |? { $_.DisplayName -eq $name } | select -First 1 }
  return $g
}

$sec = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
$cred = [pscredential]::new($ClientId,$sec)
Connect-AzAccount -ServicePrincipal -Tenant $TenantId -Credential $cred | Out-Null

$OutputDir = Ensure-Dir $OutputDir
$stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
$outCsv  = Join-Path $OutputDir "rg_permissions_ALLADH_$stamp.csv"
$outHtml = Join-Path $OutputDir "rg_permissions_ALLADH_$stamp.html"
$outJson = Join-Path $OutputDir "rg_permissions_ALLADH_$stamp.json"

$rowsProd    = Load-Expected $ProdCsvPath
$rowsNonProd = Load-Expected $NonProdCsvPath
$allOut = New-Object System.Collections.Generic.List[object]

$subs = Get-AzSubscription | ? { $_.Name -match '(?i)ADH' }
foreach($sub in $subs){
  Set-AzContext -Tenant $TenantId -SubscriptionId $sub.Id | Out-Null
  $
