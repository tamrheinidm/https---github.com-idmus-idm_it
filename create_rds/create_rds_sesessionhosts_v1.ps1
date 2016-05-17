### script to create remote desktop servers in azure.

### script requires -config parameter

Param([string]$config)

#get content of config file and populate variables 
[xml]$configcontent=Get-Content $config

$SubscriptionId = $configcontent.RDSGeneration.SubscriptionId
$GenerationNumber  = $configcontent.RDSGeneration.GenerationNumber
  
$Location  = $configcontent.RDSGeneration.Location  
$LocationCode=$configcontent.RDSGeneration.LocationCode

$NetworkName  = $configcontent.RDSGeneration.NetworkName
$NetworkRange  = $configcontent.RDSGeneration.NetworkRange
$SubnetMask  = $configcontent.RDSGeneration.SubnetMask

$NetResourceGroup  = $configcontent.RDSGeneration.NetResourceGroup 
$SourceImageResourceGroup=$configcontent.SourceImageResourceGroup
$SourceImageStorageAccount=$configcontent.SourceImageStorageAccount
 


Login-AzureRmAccount

Select-AzureRmSubscription -SubscriptionId $SubscriptionId

#create resource group

$rdsresourcegroupname='SessionHostG'+ $generationnumber + $LocationCode
New-AzureRmResourceGroup -location $location -name $rdsresourcegroupname
$rdsresourcegroup=get-azurermresourcegroup -location $location -name $rdsresourcegroupname

#get source storage account information
#$sourceimagestorage = get-azurermstorageaccount -name $SourceImageStorageAccount -ResourceGroupName $SourceImageResourceGroup
#$sourceimagestoragekey = get-azurermstorageaccountkey -name $SourceImageStorageAccount -ResourceGroupName $SourceImageResourceGroup



#create storage accounts
#premium
$rdspremiumstoragename='ishg'+ $generationnumber + $LocationCode.tolower() +'premidm'
New-AzureRmStorageAccount -Location $Location -Name $rdspremiumstoragename -ResourceGroupName $rdsresourcegroupname -type Premium_LRS
$rdspremiumstorage=get-azurermstorageaccount -name $rdspremiumstoragename -ResourceGroupName $rdsresourcegroupname
$rdspremiumstoragekey= Get-AzureRmStorageAccountKey -name $rdspremiumstoragename -ResourceGroupName $rdsresourcegroupname
write 'premium storage account created:' $rdspremiumstoragename

#locally redundant standard
$rdsstdstoragename='ishg'+ $generationnumber + $LocationCode.tolower() +'stdlidm'
New-AzureRmStorageAccount -Location $Location -Name $rdsstdstoragename -ResourceGroupName $rdsresourcegroupname -type Standard_LRS
$rdsstdstorage = get-azurermstorageaccount -Name $rdspremiumstoragename -ResourceGroupName $rdsresourcegroupname
$rdsstdstoragekey = get-azurermstorageaccountkey -Name $rdspremiumstoragename -ResourceGroupName $rdsresourcegroupname
write 'standard storage account created:' $rdsstdstoragename

# create subnet
$subnetname='SHG'+ $generationnumber + $LocationCode
$addressprefix= '10.'+$networkrange+'.'+$GenerationNumber +'.0/' + $SubnetMask
write $addressprefix

$virtualnetwork=Get-AzureRmVirtualNetwork -Name $networkname -ResourceGroupName $NetResourceGroup
Add-azurermvirtualnetworksubnetconfig -name $subnetname -AddressPrefix $addressprefix -VirtualNetwork $virtualnetwork
set-azurermvirtualnetworksubnetconfig -name $subnetname -AddressPrefix $addressprefix -VirtualNetwork $virtualnetwork
Set-AzureRmVirtualNetwork -VirtualNetwork $virtualnetwork

$virtualnetwork=Get-AzureRmVirtualNetwork -Name $networkname -ResourceGroupName $NetResourceGroup

write $virtualnetwork
$subnet=($virtualnetwork).subnets|where-object {$_.name -eq $subnetname}
write $subnet

write $Subnetname 'created'


#outer loop pulls session host configs from xml file.  nested loop builds number of machines required.

write 'starting machine type loop'
$nodecount=-1
$nodequantity= $configcontent.RDSGeneration.Catalog.ChildNodes.Count
write 'number of types of vms' $nodequantity 

$cred=Get-Credential -Message "Type the name and password of the local administrator account for rd session host" 

while ($nodecount -lt $nodequantity)

    {
        $nodecount++
        $SessionHostTypeID=$configcontent.RDSGeneration.Catalog.sessionhost[$nodecount].SessionHostTypeID
        $SessionHostTypeLabel=$configcontent.RDSGeneration.Catalog.sessionhost[$nodecount].SessionHostTypeLabel
        $vmSize=$configcontent.RDSGeneration.Catalog.sessionhost[$nodecount].vmSize
        $vmQuantity=$configcontent.RDSGeneration.Catalog.sessionhost[$nodecount].vmQuantity
        $SourceImage=$configcontent.RDSGeneration.Catalog.sessionhost[$nodecount].SourceImage
        write-host 'building quantity ' $vmQuantity  'of type '  $SessionHostTypeLabel

        # copy image from source

            #loop to create required quantity of vms per type
            $vmcount=0
            write $vmquantity
            while ($vmcount -lt $vmQuantity)
            {
                $vmcount++
                $vmname='SHG'+$GenerationNumber+ $SessionHostTypeID+ ($vmcount+9)
                $nicname=$vmname+'nic'
                $nicid='1'
                
                #create NIC
                $nic = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rdsresourcegroupname -Location $Location -SubnetId $Subnet.id 

                #$nic=new-azurermnetworkinterface -location $region -name $nicname -ResourceGroupName $vmresourcegroup -Subnet $subnet

                # Specify the name and size
                $vm=New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize
                
                #update this section to reflect use of idm image              
                    $pubName="MicrosoftWindowsServer"
                    $offerName="WindowsServer"
                    $skuName="2012-R2-Datacenter"
                    $vm=Set-AzurermVMOperatingSystem -VM $vm -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
                    $vm=Set-AzurermVMSourceImage -VM $vm -PublisherName $pubName -Offer $offerName -Skus $skuName -Version "latest"
                    $vm=Add-AzurermVMNetworkInterface -VM $vm -Id $nic.id

                # Specify the OS disk name and create the VM
                    $diskName=$vmname+"-OSDisk"
                    $storageAccount=Get-AzureRMStorageAccount -ResourceGroupName $rdsresourcegroupname -Name $rdspremiumstoragename
                    $osDiskUri=$rdspremiumstorage.PrimaryEndpoints.Blob.ToString() + "vhds/" + $vmName + $diskName  + ".vhd"
                    $vm=Set-AzureRMVMOSDisk -VM $vm -Name $diskName -VhdUri $osDiskUri -CreateOption fromImage
                New-AzureRMVM -ResourceGroupName $rdsresourcegroupname -Location $location -VM $vm

                write-host 'completed building '$vmname

    }}

    