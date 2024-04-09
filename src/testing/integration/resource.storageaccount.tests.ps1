# Describe "Storage account integration" -Tag Integration {
  BeforeAll {
      Write-Host 'Creating new environment'
  
      $ResourceGroupName = 'rg-test-' + (Get-Random)
  
      # Make sure the environment is clean by deleting the resource group
      Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue | Remove-AzResourceGroup -Force
  
      $Null = New-AzResourceGroup -Name $ResourceGroupName -Location 'westeurope' -Tag @{ env = 'integrationtesting' }
  }
  
  Describe "Deployment validation" {
      Context "Storage account integration" -Tag Integration {
          BeforeAll {
              $StorageAccount = ('tst' + (Get-Random))
              $location = 'centralindia'
              $Params = @{
                  ResourceGroupName = $ResourceGroupName
                  TemplateFile      = "$PSScriptRoot\..\..\main.bicep"
                  nameFromTemplate  = $StorageAccount
                  location = $location
              }
              New-AzResourceGroupDeployment @Params
  
              $StorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName
              Write-Host "Storage account created $($StorageAccount.StorageAccountName)"
          }
  
          It "should storage account exist" {
              $StorageAccount | Should -Not -Be $Null
          }
  
#          It "should be Standard_GRS SKU" {
#              $StorageAccount.Sku.Name | Should -Be "Standard_GRS"
#          }
  
          It "should have not public blob access" {
              $StorageAccount.AllowBlobPublicAccess | Should -Be $false
          }
  
#          It "should have minimum TLS version" {
#              $StorageAccount.MinimumTlsVersion | Should -Be "TLS1_2"
#          }
  
          It "should have only https traffic" {
              $StorageAccount.EnableHttpsTrafficOnly | Should -Be $true
          }
      }
  }
  
  AfterAll {
      Write-Host 'Tearing down environment'
      Remove-AzResourceGroup -Name $ResourceGroupName -AsJob -Force | Out-Null
  }
