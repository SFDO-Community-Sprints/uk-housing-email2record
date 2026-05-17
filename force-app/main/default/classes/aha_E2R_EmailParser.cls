global class aha_E2R_EmailParser implements Messaging.InboundEmailHandler {
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

            result.success = true;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'aha_E2R_EmailParser failed: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            result.success = false;
        }
        return result;
    }
}
