###########################################################################################
## 
##  Name:        Config Manager.ps1
##  Description: MCP / CaaS Configuration Manager tool, monitors config day-to-day
##  Author:      Jonathan Ment (Dimension Data MEA)
##  Usage:       Configure as daily task in Task Scheduler
##  Notes:
##               Requires an additional .csv file to be located in same folder
##               customerlist.csv
##                   contains:  username, password, email address
##
###########################################################################################


CLEAR

$ErrorActionPreference = "SilentlyContinue"
$WarningActionPreference = "SilentlyContinue"

$customers = Get-Content "$PSScriptRoot\customerlist.csv"
$regions   = @("Africa_AF","AsiaPacific_AP","Australia_AU","Canada_CA","Europe_EU","NorthAmerica_NA")

foreach ($customer in $customers) {
    $customer = $customer.Split(',')

    $username = $customer[0]
    $password = $customer[1]
    $emailadd = $customer[2]

    $caaspassword = ConvertTo-SecureString –String $password –AsPlainText -Force
    $credential = New-Object –TypeName System.Management.Automation.PSCredential –ArgumentList $username, $caaspassword

    foreach ($region in $regions) {

        Write-Host "Connecting to region: $region"

        New-CaasConnection -ApiCredentials $credential -Region $region -Vendor DimensionData -name TestAccount | out-null
        Set-CaasActiveConnection -name TestAccount | Out-Null

        $domains = Get-CaasNetworkDomain -WarningAction SilentlyContinue
        $vlans = Get-CaasVlan -WarningAction SilentlyContinue
        $servers = Get-CaasServer -WarningAction SilentlyContinue
        $accounts = Get-CaasAccounts -WarningAction SilentlyContinue
        $images = Get-CaasCustomerImage -WarningAction SilentlyContinue

        $orgGUID = $accounts.organizationid.guid | Get-Unique

        # Need to build up a date string for the files
        # ddmmyyyy
        $today = Get-Date -Format ddMMyyyy
        $yesterday = Get-Date((Get-Date).AddDays(-1)) -Format ddMMyyyy
        $twodays = Get-Date((Get-Date).AddDays(-2)) -Format ddMMyyyy

        # Set the output folder to be the data folder - even if it doesn't exist, create it
        $outputfile = "$PSScriptRoot\Data\"
        New-Item -ItemType Directory -Force -Path $outputfile | out-null
        $outputfile = "$outputfile$today-"

        # Now that I have gathered all the data into the various variables - need to add them to the DB
        # Call the necessary storedProcedures to get the data into the DB
        foreach ($domain in $domains) {
            write-host "Adding Network Domain:"$domain.name
            $location = $domain.datacenterId
            $domainguid = $domain.id
            $domaintype = $domain.type
            $domainname = $domain.name.ToUpper()

            $outString = "$region,Network Domain,$location,$domainguid,$domaintype,$domainname"
            $pathfile = $outputfile+"NETWORK-$orgGUID.csv"
            out-file -InputObject $outString -FilePath $pathfile -NoClobber -Append

        }
        foreach ($vlan in $vlans) {
            write-host "Adding VLAN:"$vlan.name
            $location = $vlan.datacenterId
            $vlanGUID = $vlan.id
            $vlanname = $vlan.name.ToUpper()

            # Execute the SQL Script now
            $outString = "$region,VLAN,$location,$vlanguid,$vlanname"
            $pathfile = $outputfile+"VLAN-$orgGUID.csv"
            out-file -InputObject $outString -FilePath $pathfile -NoClobber -Append
        }
        foreach ($server in $servers) {
            write-host "Adding Server:"$server.name
            $servername = $server.name.ToUpper()
            $serverguid = $server.id
            $location = $server.datacenterId
            $cpu = $server.cpu.count
            $cputype = $server.cpu.speed
            $ram = $server.memoryGb
            $monitoringType = $server.monitoring.serviceplan
            $softwarelabel = $server.softwareLabel
            $powerState = $server.started

            if ($powerstate -eq 'True') { $powerState = 'POWERED ON' } else { $powerState = 'POWERED OFF' }

            # Execute the SQL Script now
            $outString = "$region,Server,$location,$serverguid,$servername,$cpu,$cputype,$ram,$monitoringType,$softwarelabel,$powerstate"
            $pathfile = $outputfile+"SERVER-$orgGUID.csv"
            out-file -InputObject $outString -FilePath $pathfile -NoClobber -Append

            $disks = $server.disk

            foreach ($disk in $disks) {
                $diskID = $disk.Id
                $diskscsiID = $disk.scsiId
                $diskSize = $disk.sizeGb
                $diskType = $disk.speed

                # Execute the SQL Script now
                $outString = "$region,Server Disk,$serverguid,$diskID,$diskscsiID,$disksize,$disktype"
                $pathfile = $outputfile+"DISK-$orgGUID.csv"
                out-file -InputObject $outString -FilePath $pathfile -NoClobber -Append

            }
        }
        foreach ($image in $images) {
            write-host "Adding Image:"$image.name
            $imagename = $image.name.toupper()
            $location = $image.datacenterId
            $imagesize = $image.disk.sizeGB
            $imageguid = $image.id

            # Execute the SQL Script now
            $outString = "$region,Image,$location,$imageguid,$imagename,$imagesize"
            $pathfile = $outputfile+"IMAGE-$orgGUID.csv"
            out-file -InputObject $outString -FilePath $pathfile -NoClobber -Append
        }
        foreach ($account in $accounts) {
            write-host "Adding Account:"$account.Username
            $accountname = $account.username

            # Execute the SQL Script now
            $outString = "Account,$accountname"
            $pathfile = $outputfile+"ACCOUNT-$orgGUID.csv"
            out-file -InputObject $outString -FilePath $pathfile -NoClobber -Append
        }

        Remove-CaasConnection -Name Test

    }


    # First we need to strip out the duplicates in the various files - very NB, otherwise we get duplicate data in our comparison
    out-file -InputObject (Get-Content "$PSScriptRoot\Data\$today-NETWORK-$orgGUID.csv" | select -Unique) -FilePath "$PSScriptRoot\Data\$today-NETWORK-$orgGUID.csv"
    out-file -InputObject (Get-Content "$PSScriptRoot\Data\$today-VLAN-$orgGUID.csv" | select -Unique)    -FilePath "$PSScriptRoot\Data\$today-VLAN-$orgGUID.csv"
    out-file -InputObject (Get-Content "$PSScriptRoot\Data\$today-SERVER-$orgGUID.csv" | select -Unique)  -FilePath "$PSScriptRoot\Data\$today-SERVER-$orgGUID.csv"
    out-file -InputObject (Get-Content "$PSScriptRoot\Data\$today-DISK-$orgGUID.csv" | select -Unique)    -FilePath "$PSScriptRoot\Data\$today-DISK-$orgGUID.csv"
    out-file -InputObject (Get-Content "$PSScriptRoot\Data\$today-IMAGE-$orgGUID.csv" | select -Unique)   -FilePath "$PSScriptRoot\Data\$today-IMAGE-$orgGUID.csv"
    out-file -InputObject (Get-Content "$PSScriptRoot\Data\$today-ACCOUNT-$orgGUID.csv" | select -Unique) -FilePath "$PSScriptRoot\Data\$today-ACCOUNT-$orgGUID.csv"

    # This next portion of the script is per customer specified
    $compareNETWORK = Compare-Object $(Get-Content "$PSScriptRoot\Data\$yesterday-NETWORK-$orgGUID.csv") $(Get-Content "$PSScriptRoot\Data\$today-NETWORK-$orgGUID.csv")
    $compareVLAN    = Compare-Object $(Get-Content "$PSScriptRoot\Data\$yesterday-VLAN-$orgGUID.csv")    $(Get-Content "$PSScriptRoot\Data\$today-VLAN-$orgGUID.csv")
    $compareSERVER  = Compare-Object $(Get-Content "$PSScriptRoot\Data\$yesterday-SERVER-$orgGUID.csv")  $(Get-Content "$PSScriptRoot\Data\$today-SERVER-$orgGUID.csv")
    $compareDISK    = Compare-Object $(Get-Content "$PSScriptRoot\Data\$yesterday-DISK-$orgGUID.csv")    $(Get-Content "$PSScriptRoot\Data\$today-DISK-$orgGUID.csv")
    $compareIMAGE   = Compare-Object $(Get-Content "$PSScriptRoot\Data\$yesterday-IMAGE-$orgGUID.csv")   $(Get-Content "$PSScriptRoot\Data\$today-IMAGE-$orgGUID.csv")
    $compareACCOUNT = Compare-Object $(Get-Content "$PSScriptRoot\Data\$yesterday-ACCOUNT-$orgGUID.csv") $(Get-Content "$PSScriptRoot\Data\$today-ACCOUNT-$orgGUID.csv")

    # reset all the variables
    clear-Variable MyStr*


    If ($compareNETWORK) {
        foreach ($network in $compareNETWORK) {

            $sideIndicator = $network.SideIndicator
            $myNetwork     = $network.InputObject
            $myNetwork     = $myNetwork.Split(',')

            If ($sideIndicator -eq '=>') { $sideIndicator = 'New' } else { $sideIndicator = 'Retired' }

            $region     = $myNetwork[0]
            $location   = $myNetwork[2]
            $domainGUID = $myNetwork[3]
            $domaintype = $myNetwork[4]
            $domainname = $myNetwork[5]

            $MyStrNetwork = $MyStrNetwork + "<tr><td>$sideIndicator</td><td>$region</td><td>$location</td><td>$DomainName</td><td>$domaintype</td></tr>"
        }
    }
    If ($compareVLAN) {
        foreach ($vlan in $compareVLAN) {
            $sideIndicator = $vlan.SideIndicator
            $myVLAN        = $vlan.InputObject
            $myVLAN        = $myVLAN.Split(',')

            If ($sideIndicator -eq '=>') { $sideIndicator = 'New' } else { $sideIndicator = 'Retired' }

            $region   = $myVLAN[0]
            $location = $myVLAN[2]
            $vlanGUID = $myVLAN[3]
            $vlanname = $myVLAN[4]

            $MyStrVlan = $MyStrVlan + "<tr><td>$sideIndicator</td><td>$region</td><td>$location</td><td>$vlanName</td></tr>"
        }
    }
    If ($compareSERVER) {
        foreach ($server in $compareSERVER) {
            $sideIndicator = $server.SideIndicator
            $myServer      = $server.InputObject
            $myServer      = $myserver.Split(',')

            If ($sideIndicator -eq '=>') { $sideIndicator = 'New' } else { $sideIndicator = 'Retired' }

            $region     = $myServer[0]
            $location   = $myServer[2]
            $serverGUID = $myServer[3]
            $serverName = $myServer[4]
            $cpu        = $myServer[5]
            $cputype    = $myServer[6]
            $ram        = $myServer[7]
            $monitoring = $myServer[8]
            $software   = $myServer[9]
            $powerstate = $myServer[10]

            $MyStrServer = $MyStrServer + "<tr><td>$sideIndicator</td><td>$region</td><td>$location</td><td>$serverName</td><td>$serverGUID</td><td>$cpu</td><td>$cputype</td><td>$ram</td><td>$monitoring</td><td>$software</td><td>$powerstate</td></tr>"
        }
    }
    If ($compareDISK) {
        foreach ($disk in $compareDISK) {
            $sideIndicator = $disk.SideIndicator
            $myDisk        = $disk.InputObject
            $myDisk        = $myDisk.Split(',')

            If ($sideIndicator -eq '=>') { $sideIndicator = 'New' } else { $sideIndicator = 'Retired' }

            $region     = $myDisk[0]
            $serverGUID = $myDisk[2]
            $diskID     = $myDisk[3]
            $scsciID    = $myDisk[4]
            $disksize   = $myDisk[5]
            $disktype   = $myDisk[6]

            $MyStrDisk = $MyStrDisk + "<tr><td>$sideIndicator</td><td>$region</td><td>$serverGUID</td><td>$scsiID</td><td>$diskSize</td><td>$diskType</td></tr>"


        }
    }
    If ($compareIMAGE) {
        foreach ($image in $compareIMAGE) {
            $sideIndicator = $Image.SideIndicator
            $myImage       = $Image.InputObject
            $myImage       = $myImage.Split(',')

            If ($sideIndicator -eq '=>') { $sideIndicator = 'New' } else { $sideIndicator = 'Retired' }

            $region     = $myImage[0]
            $location   = $myImage[2]
            $imageGUID  = $myImage[3]
            $imageName  = $myImage[4]
            $imageSize  = $myImage[5]

            $MyStrImage = $MyStrImage + "<tr><td>$sideIndicator</td><td>$region</td><td>$location</td><td>$ImageName</td><td>$ImageSize</td></tr>"
        }
    }
    If ($compareACCOUNT) {
        foreach ($account in $compareACCOUNT) {
            $sideIndicator = $account.SideIndicator
            $myAccount     = $account.InputObject
            $myAccount     = $myAccount.Split(',')

            If ($sideIndicator -eq '=>') { $sideIndicator = 'New' } else { $sideIndicator = 'Retired' }

            $AccountName = $myAccount[1]

            $MyStrAccount = $MyStrAccount + "<tr><td>$sideIndicator</td><td>$AccountName</td></tr>"
        }
    }

    If ($MyStrNetwork) {
        # NEW DOMAIN
        $MyStr = $MyStr + "<table style='width:95%'>" +
                          "<tr><th colspan=5 bgcolor='#69BE28' style='padding-left:7px;background-color:#69BE28'><font color=white><b>Network Domains Found</th></tr>" +
                          "<tr><th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Change</th>" +
                              "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Region</th>" +
                              "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Location</th>" +
                              "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Domain Name</th>" +
                              "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Domain Type</th></tr>"
        $MyStr = $MyStr + $MyStrNetwork + "</table><br><br>"
    }

    if ($MyStrVlan) {
        # NEW VLANS
        $MyStr = $MyStr + "<table style='width:95%'>" +
                            "<tr><th colspan=4 bgcolor='#69BE28' style='padding-left:7px;background-color:#69BE28'><font color=white><b>VLANs Found</th></tr>" +
                            "<tr><th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Change</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Region</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Location</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>VLAN Name</th></tr>"
        $MyStr = $MyStr + $MyStrVlan + "</table><br><br>"
    }

    if ($MyStrServer) {
        # NEW SERVERS
        $MyStr = $MyStr + "<table style='width:95%'>" +
                            "<tr><th colspan=11 bgcolor='#69BE28' style='padding-left:7px;background-color:#69BE28'><font color=white><b>Servers Found</th></tr>" +
                            "<tr><th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Change</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Region</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Location</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Server Name</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Server UUID</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>CPU</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>CPU Type</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>RAM (GB)</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Monitoring</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Software</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>PowerState</th></tr>"
        $MyStr = $MyStr + $MyStrServer + "</table><br><br>"
    }
            
    If ($MyStrDisk) {
        # NEW DISKS
        $MyStr = $MyStr + "<table style='width:95%'><br>" +
                            "<tr><th colspan=6 bgcolor='#69BE28' style='padding-left:7px;background-color:#69BE28'><font color=white><b>Disks Found</th></tr>" +
                            "<tr><th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Change</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Region</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>serverUUID</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>scscID</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Disk Size GB</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Storage Tier</th></tr>"
        $MyStr = $MyStr + $MyStrDisk + "</table><br><br>"
    }

    If ($MyStrImage) {
        # NEW IMAGES
        $MyStr = $MyStr + "<table style='width:95%'>" +
                            "<tr><th colspan=5 bgcolor='#69BE28' style='padding-left:7px;background-color:#69BE28'><font color=white><b>Images Found</th></tr>" +
                            "<tr><th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Change</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Region</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Location</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Image Name</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Size</th></tr>"
        $MyStr = $MyStr + $MyStrImage + "</table><br><br>"
    }

    If ($MyStrAccount) {
        # NEW USERS
        $MyStr = $MyStr + "<table style='width:95%'>" +
                            "<tr><th colspan=2 bgcolor='#69BE28' style='padding-left:7px;background-color:#69BE28'><font color=white><b>Sub-Administrators Found</th></tr>" +
                            "<tr><th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Change</th>" +
                                "<th bgcolor='#808080' style='padding-left:7px;background-color:#808080'><font color=white><b>Sub-Administrator Name</th></tr>"
        $MyStr = $MyStr + $MyStrAccount + "</table><br><br>"
    }

    if ($myStr.Length -gt 0) {
        Write-Host "Sending SMTP Mail to $emailadd"
        # Can split on the semi-colon
        $emailadd = $emailadd.split(';')
        foreach ($email in $emailadd) {
            Send-MailMessage -from "no-reply@lookingglass.dimensiondata.com" -To $email -subject "Change Manager Data" -body $MyStr -BodyAsHtml -SMTPServer "127.0.0.1"
        }
    }

    write-host ""

}


# Need to delete files from 2 days ago...
Remove-Item "$PSScriptRoot\Data\$twoDays*"

 
