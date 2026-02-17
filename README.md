# Hudu-PassPortal-Migration

Easy Migration from SolarWinds Passportal to Hudu

## Prerequisites

Before getting started, make sure you have the following in place:

- Hudu instance **v2.38.0 or newer**
- Companies created in Hudu (required if you want to attribute imported items to companies)
- A Hudu API key
- A Passportal account with an API key and secret
- PowerShell **7.5.1 or later** on Windows Machine
- CSV exports for **Passwords**, placed in the `./csv-exports` directory within the project folder
- (Optional) Runbook PDF exports placed in a single, separate directory if you are migrating runbooks

> **Permissions Notice**
>
> Some scripts may require elevated permissions. Cconsider launching PowerShell (`pwsh`) with **Run as Administrator**.

---

## Terminology

Hudu and Passportal use different terminology for similar concepts. A quick mapping can help avoid confusion:

- **Asset Layout (Hudu)** → **Doctype (Passportal)**  
  Describes the structure or schema of an asset.

- **Asset (Hudu)** → **Doc (Passportal)**  
  Represents an item that belongs to a company.

---

## Setting Up the Passportal API Key & Secret

To configure Passportal access:

1. Log in to Passportal.
2. Navigate to **Settings** from the left-hand navigation menu.
3. Click **Create Access Key**.

You'll need a new environment file to store these.
Here's a quick snippet to make a new copy of this file and edit it in Notepad. You'll want to create this file to hold your environment's configuration

```
copy .\environ.example .\myenviron.ps1
notepad .\myenviron.ps1
```

<img width="2680" height="910" alt="image" src="https://github.com/user-attachments/assets/c587c88a-ec19-4ab0-b98d-2dd426988007" />

> ⚠️ **Important**: Be sure to copy both the key and secret immediately. The secret is only shown once.

---

## Exporting Password CSVs

Password exports can be initiated from the **Options** menu under **Import / Export**.

<img width="200" height="250" alt="image" src="https://github.com/user-attachments/assets/e814b04e-74f3-4c26-b193-7408e2f46177" />

- Exports must be generated **one at a time**
- Store them in a secure location
- Export **all four CSV files**
- Ensure **“Include TOTP secret”** is enabled

<img width="3614" height="1177" alt="image" src="https://github.com/user-attachments/assets/19b82f8f-7c7a-49f0-97e2-9af3a9eccc8e" />

### CSV Folder Structure

All exported CSVs should be placed together in a single directory. This directory is referenced in your environment file using the `csvPath` variable.

- The directory must contain **only** the exported CSV files
- If the directory does not exist or contains no CSVs, the script will prompt for an updated path
- Filenames may vary by company, and you may rename them if needed

However, filenames **must include** the following keywords so the script can identify them correctly:

- `Client`
- `User`
- `Vault`
- `Password`

<img width="210" height="80" alt="image" src="https://github.com/user-attachments/assets/7db55b3c-3ce7-4768-b502-96ca4b140243" />


## Exporting Runbooks (Optional)

Runbooks can be exported from the same **Import / Export** area in Passportal.

When exporting runbooks:

- Include any information you think may be useful when prompted
- Passportal merges documents during export
- The migration process later **splits them back into individual articles** when creating content in Hudu

<img width="519" height="134" alt="image" src="https://github.com/user-attachments/assets/ee601180-4b0f-479f-90c7-087c056f62b1" />

### Downloading Runbook PDFs

After initiating the export, runbooks may take some time to generate.

- Download all generated PDFs into a **new directory separate from your CSV exports**
- If you are migrating runbooks, your environment file will reference **two directories**:
  - One for CSV exports
  - One for Runbook PDFs
- If you are not migrating runbooks, only the CSV directory is required

<img width="478" height="69" alt="image" src="https://github.com/user-attachments/assets/11a7adac-7a79-4cc9-b751-acef407bd9cf" />

If you leave the page and return later:

1. Navigate back to **Import / Export**
2. Click **Generate Runbooks** again
3. Scroll to the bottom of the page to find your available PDF downloads

<img width="191" height="85" alt="image" src="https://github.com/user-attachments/assets/0bd3e7b4-014c-4fe3-b3f1-c21ec5fd3e6d" />

If the downloads are not immediately visible, wait a bit longer and refresh. Once ready, links will appear for downloading the runbooks into your designated directory.

<img width="688" height="421" alt="image" src="https://github.com/user-attachments/assets/ec55027f-6748-4abc-8e30-c9c8ae4ceaed" />

## Getting Started

### Launching Script

Getting started is really as simple as starting the main script.

---

There are a few ways to start. Probably the easiest way is to simply start the script with PowerShell.

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

If you chose the former, you will be prompted to enter the secrets needed to continue. If you did the latter, you'll only be prompted for these secrets if you left any of the values blank.

Startup will perform some self-checks (such as hudu version, powershell version) and make sure everything is in order before beginning.

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

### Runbooks Parse/Split to Hudu Article

If you elected to do so and have Runbooks PDFs exported into a single folder, that's all that you need to do for this.
The process looks like this:

A temporary processing directory will be created in Hudu-PassPortal-Migration\tmp

You'll be asked to provide a path to search for your source PDF files. If there are PDFs present, these will be converted to html with pdftohtml.exe (included in tools folder), extracting any images encountered along the way.

Then, each html file's contents will be parsed and split with some admittedly-fancy regex that extracts company name, article name, and each article contents across pages. 

Then, each of these split articles is attributed to a company and each of the extracted images is attributed to that company.

Next, articles are created with nearly-blank content, so we know where all the articles are (to add links between articles sffectively)

Then, we replace all the image links and web links with the ones we have just created. Then, each newly-split temporary article is updated with final contents. Easy!

### Manual Runbooks Migration - 

You can do this part all on it's own if needed.

All you need to do is place all PDFs from Runbooks export into a given folder. When asked at the start of Passportal Migration, you can select yes to include these. This job can also be run independently from the rest, so if you want to run this seperately, you can select 'No' and do it later by dot-sourcing it from the main project directory

```
c:\myusername\Documents\GitHub\Hudu-PassPortal-Migration> . .\jobs\convert-runbooks-to-articles.ps1
```

The rest is taken care of- images will be extracted and uploaded, and your runbooks will be split by title into individual articles for each company!

### Wrap-Up

After matching/adding passwords, you'll see some high-level information about your migration- specifically, how many assets, companies, passwords, layouts were both found in Passportal and created in Hudu

 <img width="1512" height="426" alt="image" src="https://github.com/user-attachments/assets/f1fcbcaa-8a4e-4c67-9d5e-6eb93104b7cf" />

If there are any errors that you encountered, a file corresponding to each will be found in:
.\logs\errored
Such error files are constructed so that they can be easily modified as-needed and a command can be re-issued without much trouble.

## Community & Socials

[![Hudu Community](https://img.shields.io/badge/Community-Forum-blue?logo=discourse)](https://community.hudu.com/)
[![Reddit](https://img.shields.io/badge/Reddit-r%2Fhudu-FF4500?logo=reddit)](https://www.reddit.com/r/hudu)
[![YouTube](https://img.shields.io/badge/YouTube-Hudu-red?logo=youtube)](https://www.youtube.com/@hudu1715)
[![X (Twitter)](https://img.shields.io/badge/X-@HuduHQ-black?logo=x)](https://x.com/HuduHQ)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-Hudu_Technologies-0A66C2?logo=linkedin)](https://www.linkedin.com/company/hudu-technologies/)
[![Facebook](https://img.shields.io/badge/Facebook-HuduHQ-1877F2?logo=facebook)](https://www.facebook.com/HuduHQ/)
[![Instagram](https://img.shields.io/badge/Instagram-@huduhq-E4405F?logo=instagram)](https://www.instagram.com/huduhq/)
[![Feature Requests](https://img.shields.io/badge/Feedback-Feature_Requests-brightgreen?logo=github)](https://hudu.canny.io/)
