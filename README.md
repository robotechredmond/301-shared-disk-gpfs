﻿# Windows Server 2019 General Purpose File Server Cluster with Azure Shared Disk
This template will provision a base two-node Windows Server 2019 General Purpose File Server Cluster with Azure Shared Disk.

This template creates the following resources in the selected Azure Region:

+	Proximity Placement Group and Availability Set for cluster node VMs
+   Two cluster node Azure VMs running Windows Server 2019
+   Azure VM DSC Extensions to prepare and configure the Failover Cluster
+   One Azure Shared Data Disk
+   Cluster Witness resources (either Storage Account or Shared Disk depending on value of witnessType template parameter)
+   Internal Load Balancer to provide a listener IP Address for clustered workloads that require it.
+   Azure Load Balancer for outbound SNAT support

## Prerequisites

To successfully deploy this template, the following must already be provisioned in your subscription:

+   Azure Virtual Network with subnet defined for cluster node VMs and ILB
+   Windows Server Active Directory and AD-integrated DNS reachable from Azure Virtual Network
+   Subnet IP address space defined in AD Sites and Services
+   Custom DNS Server Settings configured on Azure Virtual Network to point to DNS servers

To deploy the required Azure VNET and Active Directory infrastructure, if not already in place, you may use <a href="https://github.com/Azure/azure-quickstart-templates/tree/master/application-workloads/active-directory/active-directory-new-domain-ha-2-dc-zones">this template</a> to deploy the prerequisite infrastructure. 

## Deploying Sample Templates

Click the button below to deploy from the portal:

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Frobotechredmond%2F301-shared-disk-gpfs%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Frobotechredmond%2F301-shared-disk-gpfs%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>

## Notes

+ 	The images used to create this deployment are
	+ 	Windows Server 2019 Datacenter - Latest Image

+   Currently, Azure Shared Disk is a Preview feature and is available in a subset of Azure regions. Please review the <a href="https://docs.microsoft.com/en-us/azure/virtual-machines/windows/disks-shared-enable">official documentation</a> for more details and current status for this feature.

Tags: ``cluster, ha, shared disk, file server, windows server 2019, ws2019``
