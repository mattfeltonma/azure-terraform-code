TOKEN=$(curl -s \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net/" \
  -H "Metadata:true" \
  | jq -r '.access_token')

curl -s -H "Authorization: Bearer $TOKEN" \
  "https://kvnspdemo1pupcnc075.vault.azure.net/secrets/secret-public-word?api-version=7.0" \
  | jq -r '.value'