param location string = resourceGroup().location
resource eh 'Microsoft.EventHub/namespaces@2023-01-01-preview' = {
  name: 'ehns-iso20022-payment-stream'
  location: location
  sku: { name: 'Premium', capacity: 1 }
}
