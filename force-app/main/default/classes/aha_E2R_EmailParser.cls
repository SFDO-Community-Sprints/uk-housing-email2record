global class aha_E2R_EmailParser implements Messaging.InboundEmailHandler {

    // Attachment file extensions Document AI can process (PDF / image).
    private static final Set<String> SUPPORTED_EXT =
        new Set<String>{ 'pdf', 'png', 'jpg', 'jpeg', 'tiff', 'tif', 'bmp' };

    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();

        try {
            String emailBody;
            if (email.plainTextBody != null) {
                emailBody = email.plainTextBody;
            } else if (email.htmlBody != null) {
                emailBody = email.htmlBody.stripHtmlTags();
            } else {
                emailBody = '';
            }

            aha_E2R_Record__c record = new aha_E2R_Record__c(
                aha_Email_From__c = email.fromAddress,
                aha_Email_Subject__c = email.subject,
                aha_Email_Body__c = emailBody,
                aha_Sourced_from_Email__c = true,
                aha_AI_Enrichment_Status__c = 'Pending'
            );
            insert record;

            // Document AI POC: persist the FIRST PDF/image attachment as a File on the record, then
            // (if one was saved) enqueue async extraction — a callout can't run in this transaction.
            Boolean attachmentSaved = saveFirstSupportedAttachment(email, record.Id);
            if (attachmentSaved) {
                System.enqueueJob(new aha_E2R_DocumentAIQueueable(record.Id));
            }

            result.success = true;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'aha_E2R_EmailParser failed: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            result.success = false;
        }
        return result;
    }

    /**
     * Saves the first supported (PDF/image) binary attachment as a ContentVersion linked to the
     * record. The file name is prefixed with the record Id (<recordId>_<originalName>) for
     * traceability. Returns true if a file was saved (so the caller can enqueue extraction).
     * Failures here are logged but do NOT fail email processing — the record already exists.
     */
    private static Boolean saveFirstSupportedAttachment(Messaging.InboundEmail email, Id recordId) {
        if (email.binaryAttachments == null || email.binaryAttachments.isEmpty()) {
            return false;
        }
        try {
            for (Messaging.InboundEmail.BinaryAttachment att : email.binaryAttachments) {
                if (att == null || String.isBlank(att.fileName) || !isSupported(att.fileName)) {
                    continue;
                }

                String fileName = recordId + '_' + att.fileName;
                ContentVersion cv = new ContentVersion(
                    Title = fileName,
                    PathOnClient = fileName,
                    VersionData = att.body
                );
                insert cv;

                Id contentDocumentId = [
                    SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1
                ].ContentDocumentId;

                insert new ContentDocumentLink(
                    ContentDocumentId = contentDocumentId,
                    LinkedEntityId = recordId,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                );

                return true; // Option A: only the first supported attachment is processed
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'aha_E2R_EmailParser attachment save failed: ' + e.getMessage() + ' | ' + e.getStackTraceString());
        }
        return false;
    }

    private static Boolean isSupported(String fileName) {
        Integer dot = fileName.lastIndexOf('.');
        if (dot < 0 || dot == fileName.length() - 1) {
            return false;
        }
        return SUPPORTED_EXT.contains(fileName.substring(dot + 1).toLowerCase());
    }
}