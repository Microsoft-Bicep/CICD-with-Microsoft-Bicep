@description('Configures the location to deploy the Azure resources.')
param location string = resourceGroup().location

// Test with required parameters
module test_storage_params '../../main.bicep' = {
  name: 'testparams'
  params: {
    name: 'test90dev001'
    location: location
  }
}
