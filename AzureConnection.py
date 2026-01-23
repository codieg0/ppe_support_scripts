import requests

# Asking for their Azure Credentials
tenant_id = input("Tenant id: ")
value = input("Value id: ")
app_id = input("Application id: ")

# Payload
payload = {
    "grant_type": "client_credentials",
    "client_id": app_id,
    "client_secret": value,
    "scope": "https://management.azure.com/.default"
}

# url
url = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"

# Headers 
headers = {
    "Content-Type": "application/x-www-form-urlencoded"
}

# Post request
PostRequest = requests.post(url, data=payload, headers=headers)

if PostRequest.status_code == 200:
    print(f"\n✅Azure Acrednetials are correct✅\nCode: {PostRequest.status_code}\n")
    print(PostRequest.json())  # Print the token response
else:
    print(f"❌Incorrect Credentials❌\nCode: {PostRequest.status_code}\n")
    print(PostRequest.json())  # Print error details