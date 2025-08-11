# Hudu-PassPortal-Migration

Easy Migration from SolarWinds Passportal to Hudu

## Setup

### Prerequisites

- Hudu Instance of 2.38.0 or newer
- Companies created in Hudu if you want to attribute sharepoint items to companies
- Hudu API Key
- Passportal and Passportal API key/Secret
- Powershell 7.5.1 or later
- CSV exports for Passwords should be placed in the .\csv-exports directory within project folder

### Terminology

Hudu uses different terminology than Passportal.
For example, in Hudu, a data structure that describes an asset type is called an 'Asset Layout'. In Passportal, it is called a 'doctype'.
In Hudu, an object that represents an item that belongs to a company is called an 'Asset', whereas in Passportal, it is called a 'doc'.

### Setup Passportal API Key/Secret

To set up everything you need in passportal, you can **first log in**, **then navigate to the `Settings`** area from the left navigation menu.
<img width="2680" height="910" alt="image" src="https://github.com/user-attachments/assets/c587c88a-ec19-4ab0-b98d-2dd426988007" />
You'll then click `Create Access Key`. Take note of both values, as it will only show you the secret once.

You'll place your exported CSVs from Passportal in `.\exported-csvs\*`. This is required if you want to import passwords using this utility, since passwords are not available/exposed-to the Passportal API at present. While not including headers in your CSV export should be fine and is handled, you're encouraged to opt for including headers.

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

<img width="442" height="126" alt="image" src="https://github.com/user-attachments/assets/32d61723-3ca0-4386-bcea-c16706b6b3a2" />

### Matching / Adding Assets/Companies and Layouts

If you don't have any companies created in Hudu, it will simply create every client found in Passportal without prompting.

If there are companies present in Hudu, you'll be prompted for which company (if any) to attribute each asset to, in case you have created the company in Hudu already.

<img width="785" height="125" alt="image" src="https://github.com/user-attachments/assets/62022e0e-fc66-4d64-84af-7f7cb8910f36" />

During this prompt, you can select 1 for Skip, 2 for create new if there are no matches. Otherwise, selecting an existing company in Hudu will attribute that client's assets/objects to your selected company.

When a layout is created, you'll see the expected fields print out, like so
<img width="903" height="520" alt="image" src="https://github.com/user-attachments/assets/80aff5f9-ed5e-4986-a038-399b3cfb51ff" />

When an asset is created in Hudu, you'll see the fields that are populated print out, like so.
<img width="511" height="237" alt="image" src="https://github.com/user-attachments/assets/98cb08cf-0e47-4935-9168-0b5c828d3ad9" />

### Matching / Adding Passwords

After all companies/assets/assetlayouts are created in Hudu, your CSV exports folder will be scannec for any available CSV's.
The CSV data for each password entry is pretty sparse, so we aren't able to match passwords to assets directly. We do, however, limit your attribution options to that company's assets.

<img width="464" height="554" alt="image" src="https://github.com/user-attachments/assets/1a81ab1b-014e-42dd-bafe-f40d91a83b70" />

You can choose to attribute the printed credential to any given asset that belongs to that credential's company or you can select option 0 to attribute it to the company itself, as a generalized password, if it doesnt belong to a specific asset.

Each attributable item is listed with a number that is used for selection, and each attributable item is written with alternating colors for easy readability.

### Wrap-Up

After matching/adding passwords, you'll see some high-level information about your migration- specifically, how many assets, companies, passwords, layouts were both found in Passportal and created in Hudu

 <img width="1512" height="426" alt="image" src="https://github.com/user-attachments/assets/f1fcbcaa-8a4e-4c67-9d5e-6eb93104b7cf" />

If there are any errors that you encountered, a file corresponding to each will be found in:
.\logs\errored
Such error files are constructed so that they can be easily modified as-needed and a command can be re-issued without much trouble.



