# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ⛔ STOP. READ THIS BEFORE DOING ANYTHING. ⛔

**DO ONE THING. THEN STOP. WAIT FOR EXPLICIT INSTRUCTION BEFORE DOING THE NEXT THING.**

You are not permitted to chain actions. Ever. Not even if the next step seems obvious.

- **NEVER stage, commit, or push files without first listing exactly what you intend to include and getting explicit approval.**
- **NEVER assume scope.** If asked to "deploy to git", that means: show the plan, wait for yes, then do step 1 only, then stop.
- **NEVER add, include, or commit files that were not explicitly requested.** Ask if unsure.
- **Think before acting.** For any non-trivial action, state what you are about to do and why, and wait for confirmation.
- **Read DEPLOYMENT.md** before doing any retrieval or deployment work.

## Project Overview

This is a generic, open-source Salesforce template that routes inbound emails to `aha_E2R_Record__c` records and enriches them via an LLM Prompt Template. It is designed to be installed as a starting point and extended for any use case — the fields and prompt are intentionally minimal and generic.

## Architecture

### End-to-End Flow

1. **Email arrives** at a custom Salesforce Email Service address (Setup > Custom Code > Email Services)
2. **Apex handler** `aha_E2R_EmailParser` (`Messaging.InboundEmailHandler`) creates a `aha_E2R_Record__c` record, populating email From/Subject/Body and setting `aha_AI_Enrichment_Status__c = 'Pending'`
3. **Record-triggered Flow** `aha E2R Record - Populate from Email` fires on CREATE:
   - Calls utility Flow `aha_util_Get_Queue_Id` to resolve the `aha_E2R_Records` queue ID
   - Assigns queue as record owner
   - Invokes Prompt Template action `generatePromptResponse-aha_E2R_Record_Email`
   - Writes structured LLM response back to record fields
4. **Panel Flow** `aha E2R Record Panel` allows manual re-enrichment from the record page sidebar

### Key Components

| Type | Name | Purpose |
|------|------|---------|
| Apex | `aha_E2R_EmailParser` | InboundEmailHandler — creates E2R Record |
| Object | `aha_E2R_Record__c` | Core data record |
| Flow | `aha E2R Record - Populate from Email` | Orchestrates queue assignment + AI enrichment |
| Flow | `aha_util_Get_Queue_Id` | Utility: returns Queue ID by name |
| Flow | `aha E2R Record Panel` | Screen flow: manual re-enrichment from record sidebar |
| Queue | `aha_E2R_Records` | Owns newly created records |
| Prompt Template | `aha E2R Record - Email` | Extracts structured data from email body via LLM |
| Lightning Type | `ahaE2RRecordOBLTv1` | JSON schema that shapes the LLM's structured output |

### Prompt Template Behaviour

The template (`aha E2R Record - Email`) instructs the LLM to:
- Identify the sender name, primary date, summary, category, priority, action-required flag, and notes from the email
- Return ISO 8601 dates, booleans as `true`/`false`
- Return raw JSON only — no markdown wrapping
- Default priority to "Medium" if not explicitly stated
- Leave fields blank rather than hallucinate

## Naming Conventions

- Apex classes / custom fields: `aha_` prefix (e.g. `aha_E2R_EmailParser`, `aha_Email_From__c`)
- Flows and Prompt Templates: `aha ` prefix with spaces (e.g. `aha E2R Record - Populate from Email`)
- Lightning Types: camelCase with version suffix (e.g. `ahaE2RRecordOBLTv1`)
- Queues: snake_case with `aha_` prefix (e.g. `aha_E2R_Records`)

## Salesforce Setup Reference

- Email Service config: **Setup > Custom Code > Email Services**
- Prompt Template invoked via Flow action: `generatePromptResponse-aha_E2R_Record_Email`
- Lightning Type documentation: https://developer.salesforce.com/docs/platform/lightning-types/guide/lightning-types-object.html
- Apex Email Service documentation: https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_classes_email_inbound_what_is.htm

## Customising for Your Use Case

This template ships with a minimal, illustrative set of fields. To adapt it to a specific domain, work through these five steps in order:

### 1. Object — Add or rename fields on `aha_E2R_Record__c`
Add fields under `force-app/main/default/objects/aha_E2R_Record__c/fields/`. Field API names should follow the `aha_` prefix convention (or your own prefix).

### 2. OBLT — Update the Lightning Type schema
Edit `force-app/main/default/lightningTypes/ahaE2RRecordOBLTv1/schema.json`. Add a property for each new field you want the LLM to extract. Each property needs a `title`, `description` (tells the LLM what to look for), and a `lightning:type` (`lightning__textType`, `lightning__booleanType`, `lightning__integerType`).

### 3. Prompt Template — Update the extraction instructions
Edit `force-app/main/default/genAiPromptTemplates/aha_E2R_Record_Email.genAiPromptTemplate-meta.xml`. Update the `<content>` block to describe your domain, the email format your users send, and any field-specific extraction guidance.

### 4. Flows — Map new OBLT properties to new fields
In `force-app/main/default/flows/aha_E2R_Record_Populate_from_Email.flow-meta.xml`, add `<inputAssignments>` blocks in the `Save_Changes` record update — one per new field, referencing `LLM.structuredResponse.<propertyName>`.

In `force-app/main/default/flows/aha_E2R_Record_Panel.flow-meta.xml`, add matching `<assignmentItems>` blocks in the `MapResponse` assignment — one per new field, targeting `e2r_record.<FieldAPIName>`.

### 5. UI — Add new fields to the record page and layout
- Layout: `force-app/main/default/layouts/aha_E2R_Record__c-E2R Record Layout.layout-meta.xml`
- Flexipage: `force-app/main/default/flexipages/aha_E2R_Record_Record_Page.flexipage-meta.xml`

After making changes, redeploy following the three-step order in DEPLOYMENT.md (Lightning Type → Prompt Template → everything else).
