#---+ Extensions
#---++ NotificationPlugin
# **BOOLEAN**
# Enable debugging (debug messages will be written to data/debug.txt)
$Foswiki::cfg{Plugins}{NotificationPlugin}{Debug} = '0';
#
# **STRING 300**
# Regular expression of mail addresses that we are allowed to send to. To send to multiple addresses you can write (address1|address2).
$Foswiki::cfg{Plugins}{NotificationPlugin}{SENDER} = 'Lame Default <webmaster@localhost>';
#
1;
