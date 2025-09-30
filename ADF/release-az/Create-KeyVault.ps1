param (
    [String]$Environment = 'D1',
    [String]$App = 'BOT',
    [Parameter(Mandatory)]
    [String]$Location,
    [Parameter(Mandatory)]
    [String]$OrgName,
    [string]$RoleName = 'Key Vault Administrator',
    
    # Default to false for lab
    [switch]$EnablePurgeProtection
)

Write-Output "$('-'*50)"
Write-Output $MyInvocation.MyCommand.Source

$LocationLookup = Get-Content -Path $PSScriptRoot\..\bicep\global\region.json | ConvertFrom-Json
$Prefix = $LocationLookup.$Location.Prefix

# Azure Blob Container Info
[String]$KVName = "${Prefix}-${OrgName}-${App}-${Environment}-kv".tolower()
[String]$RGName = "${Prefix}-${OrgName}-${App}-RG-${Environment}"


# Primary RG
Write-Verbose -Message "KeyVault RGName:`t $RGName" -Verbose
if (! (Get-AzResourceGroup -Name $RGName -EA SilentlyContinue))
{
    try
    {
        New-AzResourceGroup -Name $RGName -Location $Location -ErrorAction stop
    }
    catch
    {
        Write-Warning $_
        break
    }
}

# Primary KV
Write-Verbose -Message "KeyVault Name:`t`t $KVName" -Verbose
if (! (Get-AzKeyVault -Name $KVName -EA SilentlyContinue))
{
    try
    {
        # Build params and add -EnableRbacAuthorization only if supported by current Az.KeyVault module
        $usingRbacMode = $false
        $kvCommand = Get-Command -Name New-AzKeyVault -ErrorAction SilentlyContinue
        if ($kvCommand -and $kvCommand.Parameters.ContainsKey('EnableRbacAuthorization'))
        {
            $usingRbacMode = $true
        }

        $kvParams = @{
            Name                         = $KVName
            ResourceGroupName            = $RGName
            Location                     = $Location
            EnabledForDeployment         = $true
            EnabledForTemplateDeployment = $true
            EnablePurgeProtection        = [bool]$EnablePurgeProtection
            Sku                          = 'Standard'
            ErrorAction                  = 'Stop'
        }
        if ($usingRbacMode)
        {
            $kvParams['EnableRbacAuthorization'] = $true
        }

        New-AzKeyVault @kvParams
    }
    catch
    {
        Write-Warning $_
        break
    }
}

# Primary KV RBAC or Access Policy (fallback when RBAC mode isn't available)
Write-Verbose -Message "Primary KV Name:`t $KVName RBAC for KV Contributor" -Verbose
if (Get-AzKeyVault -Name $KVName -EA SilentlyContinue)
{
    try
    {
        $CurrentUserId = Get-AzContext | ForEach-Object account | ForEach-Object Id

        # Determine if the created/existing vault is in RBAC mode
        $kv = Get-AzKeyVault -Name $KVName -EA SilentlyContinue
        $usingRbacMode = $false
        if ($kv)
        {
            $member = $kv | Get-Member -Name EnableRbacAuthorization -ErrorAction SilentlyContinue
            if ($member)
            {
                $usingRbacMode = [bool]$kv.EnableRbacAuthorization
            }
        }

        if ($usingRbacMode)
        {
            if (! (Get-AzRoleAssignment -ResourceGroupName $RGName -SignInName $CurrentUserId -RoleDefinitionName $RoleName))
            {
                New-AzRoleAssignment -ResourceGroupName $RGName -SignInName $CurrentUserId -RoleDefinitionName $RoleName -Verbose
            }
        }
        else
        {
            # Fallback for environments without RBAC-enabled Key Vaults: grant access policy to current user
            Set-AzKeyVaultAccessPolicy -VaultName $KVName -UserPrincipalName $CurrentUserId `
                -PermissionsToSecrets @('get','list','set','delete','backup','restore','recover') `
                -PermissionsToCertificates @('get','list','import','delete') `
                -PermissionsToKeys @('get','list','create','delete') -Verbose
        }
    }
    catch
    {
        Write-Warning $_
        break
    }
}

# # LocalAdmin Creds
# Write-Verbose -Message "Primary KV Name:`t $KVName Secret for [localadmin]" -Verbose
# if (! (Get-AzKeyVaultSecret -VaultName $KVName -Name localadmin -EA SilentlyContinue))
# {
#     try
#     {
#         Write-Warning -Message 'vmss Username is: [botadmin]'
#         $vmAdminPassword = (Read-Host -AsSecureString -Prompt 'Enter the vmss password')
#         Set-AzKeyVaultSecret -VaultName $KVName -Name localadmin -SecretValue $vmAdminPassword
#     }
#     catch
#     {
#         Write-Warning $_
#         break
#     }
# }



