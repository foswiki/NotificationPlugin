#---+ Extensions
#---++ NotificationPlugin
# **BOOLEAN**
# Enable debugging (debug messages will be written to data/debug.txt)
$Foswiki::cfg{Plugins}{NotificationPlugin}{Debug} = '0';
#
# **BOOLEAN**
# Enables the "Immediate Notify" functionality.  If disabled, the TIN and WIN
# buttons will not be displayed, and the beforeSafeHandler will be disabled.
# Note that the email processing in the beforeSafeHandler can slow down or
# block the save if the email server has issues.
$Foswiki::cfg{Extensions}{NotificationPlugin}{EnableImmediateNotify} = $TRUE;
#
# **BOOLEAN**
# Enables the "Normal Notify" functionality.  If disabled, the TN and WN
# buttons will not be displayed. This function is disabled by default as the
# MailerContrib provides richer functionality.
$Foswiki::cfg{Extensions}{NotificationPlugin}{EnableNormalNotify} = $FALSE;
1;
