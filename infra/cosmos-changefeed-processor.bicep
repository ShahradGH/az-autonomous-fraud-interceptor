param location string = resourceGroup().location
resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: 'cosmos-fraud-velocity-graph'
  location: location
  properties: { databaseAccountOfferType: 'Standard' }
}
