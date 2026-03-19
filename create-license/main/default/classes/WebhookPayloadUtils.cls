public class WebhookPayloadUtils {
    // Replicated notification webhooks send customer_id as
    // "CustomerName (actualId)". Extract the bare ID from inside
    // the parentheses, or return the original value if the format
    // doesn't match.
    public static String parseCustomerId(String rawId) {
        if (String.isBlank(rawId)) {
            return rawId;
        }
        Integer open = rawId.lastIndexOf('(');
        if (open >= 0 && rawId.endsWith(')')) {
            return rawId.substring(open + 1, rawId.length() - 1);
        }
        return rawId;
    }

    public static Date parseDate(String dateString) {
        if (String.isBlank(dateString)) {
            return null;
        }
        try {
            if (dateString.contains('T')) {
                dateString = dateString.substringBefore('T');
            }
            return Date.valueOf(dateString);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'WebhookPayloadUtils: failed to parse date');
            return null;
        }
    }
}
