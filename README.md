# Hudu-PassPortal-Migration

Easy Migration from SolarWinds Passportal to Hudu

## Setup

### Prerequisites

- Hudu Instance of 2.38.0 or newer
- Companies created in Hudu if you want to attribute sharepoint items to companies
- Hudu API Key
- Passportal and Passportal API key/Secret
- Powershell 7.5.1 or later
- [optional] CSV exports for future implementation of passwords transfer



### Setup Passportal API Key/Secret

To set up everything you need in passportal, you can **first log in**, **then navigate to the `Settings`** area from the left navigation menu.
<img width="2680" height="910" alt="image" src="https://github.com/user-attachments/assets/c587c88a-ec19-4ab0-b98d-2dd426988007" />
You'll then click `Create Access Key`. Take note of both values, as it will only show you the secret once.

Shortly, we'll add a feature that migrates your passwords (via export) from passportal. Since passwords are not exposed via api, we'll have to load these from CSV. This feature is still WIP, however, when completed, you'll place in `.\exported-csvs\*`

<img width="295" height="94" alt="image" src="https://github.com/user-attachments/assets/c70c9d0a-fc7f-42e4-bdf3-324507cc7d1d" />

## Getting Started

### Launching Script
getting started is really as simple as starting the main script.

---

There are a few ways to start. First, and probably easiest, you can simply start the script.

```
 . .\Passportal-Migration.ps1
```
Alternatively, you can make a copy of the environment example file, edit in your values, and run when filled out.
```
copy .\environ.example .\myenviron.ps1
notepad .\myenviron.ps1
write-host "...everything is edited!"
 . .\Passportal-Migration.ps1
```

If you chose the former, you will be prompted to enter the secrets needed to continue. If you did the latter, you'll only be prompted for these secrets if you left something empty.
Startup will perform some self-checks (like hudu version, powershell version) and make sure everything is in order before beginning.

<img width="710" height="292" alt="image" src="https://github.com/user-attachments/assets/161bb82e-b973-46d8-8d4e-c482a7257e97" />

If you are experiencing trouble authenticating to Passportal, you might try switching the 'secret key' and 'key id' in your environment file or when you are prompted, they are about the same length and easy to mix-up.

We'll then load all the data possible from the Passportal API, which can take a while. 

<img width="1229" height="157" alt="image" src="https://github.com/user-attachments/assets/ea99168e-b0ad-4820-8600-2c4379e381a2" />

## Todo
