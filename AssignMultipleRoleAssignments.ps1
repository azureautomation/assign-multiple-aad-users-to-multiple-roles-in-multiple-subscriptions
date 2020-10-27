$VerbosePreference = "Continue"

#Clear and prepare SelectedUsers array
$SelectedUsers = @()
#Clear and prepare SelectedUsers array
$SelectedGroups = @()


#Get Azure Module Version
$AzureModuleVersion = (Get-Module -Name "AzureRM" -ListAvailable).Version
Write-Verbose "Azure Version: $($AzureModuleVersion.Major)"
switch ($AzureModuleVersion.Major) {
    {$_ -ge 4} {
        $SubIdVar = "Id"
        $SubNameVar = "Name"
        break}
    {$_ -lt 4} {
        $SubIdVar = "SubscriptionId"
        $SubNameVar = "SubscriptionName"
        break}
}

Write-Host `r`n
Write-Host -ForegroundColor Cyan "The selection grid may take a while to display, depending on the number of users returned"

#LoopStart: until you've finished adding more users
do {
    #Prompt user for string to search users display name
    $UserSearch = Read-Host -Prompt "Enter Display Name search string"
    #Clear and prepare Users array
    $Users = @()
    $Groups = @()

    #Return all users matching the search string
    $Users = Get-AzureRmADUser -SearchString $UserSearch
    $Groups = Get-AzureRmADGroup -SearchString $UserSearch  | Where-Object {$_.SecurityEnabled -eq $true}

    #If we found some users then;
    if ($Users.Count -ne 0) {
        #If only one user was found, add it 
        if ($Users.Count -eq 1) {
            $SelectedUsers += $Users
        } else {
            #If more than one user was found, use a GridView to select the required users.
            $SelectedUsers += $Users | select DisplayName, UserPrincipalName, ID, Type | Sort-Object Name | Out-GridView -Title "Select Users" -PassThru
        }
        #Write the selected users to output
        Write-Output  $SelectedUsers | select DisplayName, UserPrincipalName, ID, Type | Sort-Object DisplayName | Format-Table -AutoSize
    }
    #If we found some groups then;
    if ($Groups.Count -ne 0) {
        #If only one group was found, add it 
        if ($Groups.Count -eq 1) {
            $SelectedGroups += $Groups
        } else {
            #If more than one group was found, use a GridView to select the required groups.
            if ($Groups.Count -le 10) {
                $SelectedGroups += $Groups | select DisplayName, ID, Type,  @{Name="MemberCount";Exp={(Get-AzureRmADGroupMember -GroupObjectId $_.Id).Count}} | Sort-Object DisplayName | Out-GridView -Title "Select Groups" -PassThru
            } else {
                $SelectedGroups += $Groups | select DisplayName, ID, Type, @{Name="MemberCount";Exp={0}} | Sort-Object DisplayName | Out-GridView -Title "Select Groups" -PassThru
            }
        }
        #Write the selected groups to output
        Write-Output  $SelectedGroups | select DisplayName, ID | Sort-Object DisplayName | Format-Table -AutoSize
    }

    #Prompt user to keep adding more users
    $KeepAdding = Read-Host -Prompt "Add more users/groups? (Y/N)"

    #LoopEnd: until you've finished adding more users
} until ($KeepAdding -notin ('Y','y'))

#If there are no selected users then exit out, otherwise continue
if (($SelectedUsers.Count -eq 0) -and ($SelectedGroups.Count -eq 0)) {
    Write-Host `r`n
    Write-Host -ForegroundColor Cyan "No Users selected, we're done here"
} else {
    
    #Write out selected users and get confirmation to continue
    $SelectedResults = @(($SelectedUsers | Select-Object DisplayName, @{Name="UPN";Exp={$_.UserPrincipalName}}, Id, Type,@{Name="MemberCount";Exp={$null}}),($SelectedGroups | Select-Object DisplayName, @{Name="UPN";Exp={$null}},Id,Type, @{Name="MemberCount";Exp={(Get-AzureRmADGroupMember -GroupObjectId $_.Id).Count}}))
    Write-Output  $SelectedResults | select DisplayName, UserPrincipalName, ID, Type, MemberCount | Sort-Object DisplayName | Format-Table -AutoSize
    $Cont = Read-Host "Continue (Y/N)"

    if ($Cont -in ('Y','y')) {
        
        $SelectedSubscriptions = @()

        $SelectedSubscriptions = Get-AzureRmSubscription | Select "$($SubNameVar)", "$($SubIdVar)" | Out-GridView -Title "Select Subscriptions (Ctrl/Shift click for multiples)" -PassThru 

        $Roles = @()
        $Roles = Get-AzureRmRoleDefinition | select Name, Description, IsCustom, Id | Sort-Object -Property @{Expression = {$_.IsCustom}; Ascending = $false}, Name | Out-GridView -title "Select Roles  (Ctrl/Shift click for multiples)" -PassThru
        Select-AzureRmSubscription -SubscriptionId $SelectedSubscriptions[0].$SubIdVar

        foreach ($Sub in $SelectedSubscriptions) {
            foreach ($User in $SelectedUsers) {
                foreach ($Role in $Roles) {
                    New-AzureRmRoleAssignment -ObjectId $User.Id -Scope "/subscriptions/$($Sub.$SubIdVar)" -RoleDefinitionId $Role.Id -ErrorAction Continue
                    Write-Output "add User:$($User.displayname) to $($Role.Name)"
                }
            }
            foreach ($Group in $SelectedGroups) {
                foreach ($Role in $Roles) {
                    New-AzureRmRoleAssignment -ObjectId $Group.Id -Scope "/subscriptions/$($Sub.$SubIdVar)" -RoleDefinitionId $Role.Id -ErrorAction Continue
                    Write-Output "add Group:$($Group.displayname) to $($Role.Name)"
                }
            }
        }
    } else {
        Write-Host `r`n
        Write-Host -ForegroundColor Cyan "You've selected not to continue, we're done here"
    }
}
