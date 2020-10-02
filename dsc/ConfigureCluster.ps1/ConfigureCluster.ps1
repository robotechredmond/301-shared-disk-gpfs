#
# Copyright 2020 Microsoft Corporation. All rights reserved."
#

configuration ConfigureCluster
{
    param
    (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$AdminCreds,

        [Parameter(Mandatory)]
        [String]$ClusterName,

        [Parameter(Mandatory)]
        [String]$FSName,

        [Parameter(Mandatory)]
        [String]$ShareName,

        [Parameter(Mandatory)]
        [String]$NamePrefix,

        [Parameter(Mandatory)]
        [Int]$VMCount,

        [Parameter(Mandatory)]
        [String]$WitnessType,

        [Parameter(Mandatory)]
        [String]$ListenerIPAddress,

        [Parameter(Mandatory)]
        [Int]$ListenerProbePort,

        [Int]$ListenerPort,

        [Int]$DataDiskSizeGB,

        [String]$WitnessStorageName,

        [System.Management.Automation.PSCredential]$WitnessStorageKey
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration, ComputerManagementDsc, ActiveDirectoryDsc

    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("$($Admincreds.UserName)@${DomainName}", $Admincreds.Password)

    [System.Collections.ArrayList]$Nodes = @()
    For ($count = 1; $count -lt $VMCount; $count++) {
        $Nodes.Add($NamePrefix + $Count.ToString())
    }
  
    Node localhost
    {

        Script dscRebootFix1 {
            SetScript            = "`$taskTrigger = New-ScheduledTaskTrigger -AtStartup; `$taskAction = New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument '-Command Start-Sleep 300; Restart-Computer -Force'; `$taskSettings = New-ScheduledTaskSettingsSet; `$taskCreds = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest; `$task = New-ScheduledTask -Action `$taskAction -Trigger `$taskTrigger -Settings `$taskSettings -Principal `$taskCreds; Register-ScheduledTask -TaskName 'dscRebootFix1' -InputObject `$task"
            TestScript           = "if ((Get-ScheduledTask -TaskName 'dscRebootFix1' -ErrorAction SilentlyContinue).State -ne `$null) { Stop-ScheduledTask -TaskName 'dscRebootFix1'; (Disable-ScheduledTask -TaskName 'dscRebootFix1').State -eq 'Disabled' } else { `$false }"
            GetScript            = "@{Ensure = if ((Get-ScheduledTask -TaskName 'dscRebootFix1' -ErrorAction SilentlyContinue).State -ne `$null) {'Present'} else {'Absent'}}"
        }
        
        WindowsFeature FC {
            Name   = "Failover-Clustering"
            Ensure = "Present"
            DependsOn = "[Script]dscRebootFix1"
        }

        WindowsFeature FCPS {
            Name      = "RSAT-Clustering-PowerShell"
            Ensure    = "Present"
            DependsOn = "[WindowsFeature]FC"
        }

        WindowsFeature FCCmd {
            Name      = "RSAT-Clustering-CmdInterface"
            Ensure    = "Present"
            DependsOn = "[WindowsFeature]FCPS"
        }

        WindowsFeature ADPS {
            Name      = "RSAT-AD-PowerShell"
            Ensure    = "Present"
            DependsOn = "[WindowsFeature]FCCmd"
        }

        WindowsFeature FS
        {
            Name = "FS-FileServer"
            Ensure = "Present"
        }

        WaitForADDomain DscForestWait 
        { 
            DomainName              = $DomainName 
            Credential              = $DomainCreds
            WaitForValidCredentials = $True
            WaitTimeout             = 600
            RestartCount            = 3
            DependsOn               = "[WindowsFeature]ADPS"
        }

        Computer DomainJoin
        {
            Name       = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $DomainCreds
            DependsOn  = "[WaitForADDomain]DscForestWait"
        }

        Script CreateCluster {
            SetScript            = "New-Cluster -Name ${ClusterName} -Node ${env:COMPUTERNAME} -NoStorage "
            TestScript           = "(Get-Cluster -ErrorAction SilentlyContinue).Name -eq '${ClusterName}'"
            GetScript            = "@{Ensure = if ((Get-Cluster -ErrorAction SilentlyContinue).Name -eq '${ClusterName}') {'Present'} else {'Absent'}}"
            PsDscRunAsCredential = $DomainCreds
            DependsOn            = @("[Computer]DomainJoin", "[WindowsFeature]FS")
        }

        foreach ($Node in $Nodes) {
            Script "AddClusterNode_${Node}" {
                SetScript            = "Add-ClusterNode -Name ${Node} -NoStorage"
                TestScript           = "'${Node}' -in (Get-ClusterNode).Name"
                GetScript            = "@{Ensure = if ('${Node}' -in (Get-ClusterNode).Name) {'Present'} else {'Absent'}}"
                PsDscRunAsCredential = $DomainCreds
                DependsOn            = "[Script]CreateCluster"
            }
        }

        Script FormatSharedDisks {
            SetScript  = "Get-Disk | Where-Object PartitionStyle -eq 'RAW' | Initialize-Disk -PartitionStyle GPT -PassThru -ErrorAction SilentlyContinue | New-Partition -AssignDriveLetter -UseMaximumSize -ErrorAction SilentlyContinue | Format-Volume -FileSystem NTFS -Confirm:`$false"
            TestScript = "(Get-Disk | Where-Object PartitionStyle -eq 'RAW').Count -eq 0"
            GetScript  = "@{Ensure = if ((Get-Disk | Where-Object PartitionStyle -eq 'RAW').Count -eq 0) {'Present'} else {'Absent'}}"
            DependsOn  = "[Script]CreateCluster"
        }

        Script AddClusterDisks {
            SetScript  = "Get-ClusterAvailableDisk | Add-ClusterDisk"
            TestScript = "(Get-ClusterAvailableDisk).Count -eq 0"
            GetScript  = "@{Ensure = if ((Get-ClusterAvailableDisk).Count -eq 0) {'Present'} else {'Absent'}}"
            DependsOn  = "[Script]FormatSharedDisks"
        }

        Script ClusterWitness {
            SetScript  = "if ('${WitnessType}' -eq 'Cloud') { Set-ClusterQuorum -CloudWitness -AccountName ${WitnessStorageName} -AccessKey $($WitnessStorageKey.GetNetworkCredential().Password) } else { Set-ClusterQuorum -DiskWitness `$((Get-ClusterGroup -Name 'Available Storage' | Get-ClusterResource | ? ResourceType -eq 'Physical Disk' | Sort-Object Name | Select-Object -Last 1).Name) }"
            TestScript = "((Get-ClusterQuorum).QuorumResource).Count -gt 0"
            GetScript  = "@{Ensure = if (((Get-ClusterQuorum).QuorumResource).Count -gt 0) {'Present'} else {'Absent'}}"
            DependsOn  = "[Script]AddClusterDisks"
        }

        Script IncreaseClusterTimeouts {
            SetScript  = "(Get-Cluster).SameSubnetDelay = 2000; (Get-Cluster).SameSubnetThreshold = 15; (Get-Cluster).CrossSubnetDelay = 3000; (Get-Cluster).CrossSubnetThreshold = 15"
            TestScript = "(Get-Cluster).SameSubnetDelay -eq 2000 -and (Get-Cluster).SameSubnetThreshold -eq 15 -and (Get-Cluster).CrossSubnetDelay -eq 3000 -and (Get-Cluster).CrossSubnetThreshold -eq 15"
            GetScript  = "@{Ensure = if ((Get-Cluster).SameSubnetDelay -eq 2000 -and (Get-Cluster).SameSubnetThreshold -eq 15 -and (Get-Cluster).CrossSubnetDelay -eq 3000 -and (Get-Cluster).CrossSubnetThreshold -eq 15) {'Present'} else {'Absent'}}"
            DependsOn  = "[Script]ClusterWitness"
        }

        Script ClusterFileServerRole {
            SetScript  = "Add-ClusterFileServerRole -Name ${FSName} -Storage `$((Get-ClusterGroup -Name 'Available Storage' | Get-ClusterResource | ? ResourceType -eq 'Physical Disk').Name) -StaticAddress ${ListenerIPAddress}"
            TestScript = "(Get-ClusterResource -Name 'File Server (\\${FSName})' -ErrorAction SilentlyContinue).State -eq 'Online'"
            GetScript  = "@{Ensure = if ((Get-ClusterResource -Name 'File Server (\\${FSName})' -ErrorAction SilentlyContinue).State -eq 'Online') {'Present'} else {'Absent'}}"
            PsDscRunAsCredential = $DomainCreds
            DependsOn  = "[Script]IncreaseClusterTimeouts"
        }

        Script ClusterIPAddress {
            SetScript  = "Get-ClusterResource -Name 'IP Address ${ListenerIPAddress}' | Set-ClusterParameter -Name ProbePort ${ListenerProbePort}; Stop-ClusterGroup -Name ${FSName}; Start-ClusterGroup -Name ${FSName}"
            TestScript = "(Get-ClusterResource -Name 'IP Address ${ListenerIPAddress}' -ErrorAction SilentlyContinue | Get-ClusterParameter -Name ProbePort).Value -eq ${ListenerProbePort}"
            GetScript  = "@{Ensure = if ((Get-ClusterResource -Name 'IP Address ${ListenerIPAddress}' -ErrorAction SilentlyContinue | Get-ClusterParameter -Name ProbePort).Value -eq ${ListenerProbePort}) {'Present'} else {'Absent'}}"
            DependsOn  = "[Script]ClusterFileServerRole"
        }
        
        Script SMBShare {
            SetScript  = "Set-Variable -Name DriveLetter -Value `$(Get-ChildItem -Path Function:[F-Z]: -Name | ? { (Test-Path `$_) } | Select-Object -First 1) ; New-Item -Path `${DriveLetter}\${ShareName} -ItemType Directory; New-SmbShare -Name ${ShareName} -Path `${DriveLetter}\${ShareName} -FullAccess ${DomainName}\$($AdminCreds.Username)"
            TestScript = "(Get-SmbShare -Name ${ShareName} -ErrorAction SilentlyContinue).ShareState -eq 'Online'"
            GetScript  = "@{Ensure = if ((Get-SmbShare -Name ${ShareName} -ErrorAction SilentlyContinue).ShareState -eq 'Online') {'Present'} else {'Absent'}}"
            DependsOn  = "[Script]ClusterIPAddress"
        }

        Script FirewallRuleProbePort {
            SetScript  = "Remove-NetFirewallRule -DisplayName 'Failover Cluster - Probe Port' -ErrorAction SilentlyContinue; New-NetFirewallRule -DisplayName 'Failover Cluster - Probe Port' -Profile Domain -Direction Inbound -Action Allow -Enabled True -Protocol 'tcp' -LocalPort ${ListenerProbePort}"
            TestScript = "(Get-NetFirewallRule -DisplayName 'Failover Cluster - Probe Port' -ErrorAction SilentlyContinue | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue).LocalPort -eq ${ListenerProbePort}"
            GetScript  = "@{Ensure = if ((Get-NetFirewallRule -DisplayName 'Failover Cluster - Probe Port' -ErrorAction SilentlyContinue | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue).LocalPort -eq ${ListenerProbePort}) {'Present'} else {'Absent'}}"
            DependsOn  = "[Script]SMBShare"
        }

        LocalConfigurationManager {
            RebootNodeIfNeeded = $True
        }

    }
}
