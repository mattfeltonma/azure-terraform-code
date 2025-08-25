TOKEN=$(curl -s \
'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net/' \
-H Metadata:true \
| jq -r '.access_token')

curl -s -H "Authorization: Bearer $TOKEN" \
 "https://kvnspkveus2489.vault.azure.net/secrets/special?api-version=7.0" \
| jq -r '.value'