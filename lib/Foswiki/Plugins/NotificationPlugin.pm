# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
package Foswiki::Plugins::NotificationPlugin;

use vars qw(
  $web $topic $user $installWeb $VERSION $RELEASE $pluginName
  $sender @users $debug @sections
);

$VERSION = '1.30';
$RELEASE = '24 Feb 2017';
our $SHORTDESCRIPTION =
  'Send fine grained notifications of topics you are interested in';

$pluginName = 'NotificationPlugin';    # Name of this Plugin

# =========================
sub initPlugin {
    ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 1 ) {
        Foswiki::Func::writeWarning(
            "Version mismatch between $pluginName and Plugins.pm");
        return 0;
    }

    @users    = getUsers();
    @sections = (
        "(Topic) immediate notifications",
        "(Web) immediate notifications",
        "(Regex) immediate notifications",
        "(Topic) notifications",
        "(Web) notifications",
        "(Regex) notifications"
    );

    $debug = $Foswiki::cfg{Plugins}{$pluginName}{Debug} || 0;

# KISS:
# $sender = $Foswiki::cfg{Plugins}{$pluginName}{SENDER} || "Foswiki NotificationPlugin";
    $sender = $Foswiki::cfg{WebMasterEmail};

    # Plugin correctly initialized
    Foswiki::Func::writeDebug(
        "- Foswiki::Plugins::${pluginName}::initPlugin( $web.$topic ) is OK")
      if $debug;
    return 1;
}

# =========================
sub commonTagsHandler {
    ### my ( $text, $topic, $web ) = @_;

    Foswiki::Func::writeDebug(
        "- ${pluginName}::commonTagsHandler( $_[2].$_[1] )")
      if $debug;

    # This is the place to define customized tags and variables
    # Called by sub handleCommonTags, after %INCLUDE:"..."%

    # do custom extension rule, like for example:
    $_[0] =~ s/%NTF\{(.*?)\}%/&showNotifyButtons($1)/ge;
}

# =========================
sub beforeSaveHandler {
    ### my ( $text, $topic, $web ) = @_;

    Foswiki::Func::writeDebug(
        "- ${pluginName}::beforeSaveHandler( $_[2].$_[1] )")
      if $debug;

    my $wikiUser = Foswiki::Func::userToWikiName( $user, 1 );
    my @notifyUsers = ();
    push( @notifyUsers, getUsersToNotify( $_[2], $_[1], 0 ) );
    push( @notifyUsers, getUsersToNotify( $_[2], $_[1], 1 ) );
    push( @notifyUsers, getUsersToNotify( $_[2], $_[1], 2 ) );

    Foswiki::Func::writeDebug("COUNT = $#notifyUsers");
    my $subject = "Topic $_[2].$_[1] has been changed by $wikiUser.";
    my $body =
        "Topic "
      . Foswiki::Func::getScriptUrl( $_[2], $_[1], "view" )
      . " has been changed by $wikiUser at "
      . Foswiki::Func::formatTime( time() ) . " GMT";
    notifyUsers( \@notifyUsers, $subject, $body );
}

# =========================
sub getUsers {
    my @result;

    my @topics = Foswiki::Func::getTopicList( $Foswiki::cfg{UsersWebName} );

    foreach my $name (@topics) {
        next unless $name =~ /^(.*)NotifyList$/;

        #Foswiki::Func::writeDebug( "NAME = $1" );
        $result[ ++$#result ] = $1 if ( $1 ne "" );
    }

    #Foswiki::Func::writeDebug( "USERS = $#result" );
    return @result;
}

sub getUsersToNotify {
    my ( $tweb, $ttopic, $section ) = @_;
    my @result;

    #Foswiki::Func::writeDebug( "TYPE = $type" );
    foreach my $tmp (@users) {

        #Foswiki::Func::writeDebug( "TMP = $tmp" );
        my $text = Foswiki::Func::readTopic( $Foswiki::cfg{UsersWebName},
            "$tmp" . "NotifyList" );
        my $test = "";
        foreach my $line ( split( /\n/, $text ) ) {
            $line =~ s/\s+$//;

            #Foswiki::Func::writeDebug( "LINE = $line" );
            #Foswiki::Func::writeDebug( "TEST = $test" );
            next unless $line;
            $test = "" if ( ( $test ne "" ) && ( $line !~ /^\s*\*/ ) );

            #Foswiki::Func::writeDebug( "TEST = $test" );
            if ( $test eq "Topic" ) {
                $line =~ /\s*\*\s(.*?)\.(.*)/;
                if ( ( $tweb eq $1 ) && ( $ttopic eq $2 ) ) {
                    $result[ ++$#result ] = $tmp;
                    last;
                }
            }
            elsif ( $test eq "Web" ) {
                $line =~ /\s*\*\s(.*)/;
                if ( $tweb eq $1 ) {
                    $result[ ++$#result ] = $tmp;
                    last;
                }
            }
            elsif ( $test eq "Regex" ) {
                $line =~ /\s*\*\s(.*)/;
                if ( "$tweb.$ttopic" =~ /$1/ ) {
                    $result[ ++$#result ] = $tmp;
                    last;
                }
            }
            $test = $1 if ( $line =~ /$sections[$section]/ );
        }
    }
    return @result;
}

sub getNotificationsOfUser {
    my $who     = shift;
    my $section = shift;
    my $text    = shift || "";
    my $meta;

#Foswiki::Func::writeDebug( "NTF:getNotificationsOfUser: WHO = $who, SCT = $section, TXT = ".length( $text ) );
    ( $meta, $text ) = checkUserNotifyList($who) if ( $text eq "" );
    my @result;

    #Foswiki::Func::writeDebug( "USER = $tuser" );
    $test = "";
    foreach my $line ( split( /\n/, $text ) ) {

        #Foswiki::Func::writeDebug( "LINE = $line" );
        while ( ( $line =~ /\n$/ ) || ( $line =~ /\r$/ ) ) {
            chop($line);
        }
        last if ( ( $test ne "" ) && ( $line !~ /^\s*\*/ ) );
        if ( $test eq "Topic" ) {
            $line =~ /\s*\*\s(.*?)\.(.*)/;

            #Foswiki::Func::writeDebug( "TOPIC = $1.$2" );
            $result[ ++$#result ] = "$1.$2";
        }
        elsif ( ( $test eq "Web" ) || ( $test eq "Regex" ) ) {
            $line =~ /\s*\*\s(.*)/;

            #Foswiki::Func::writeDebug( "RESULT = $1" );
            $result[ ++$#result ] = $1;
        }
        $test = $1 if ( $line =~ /$sections[$section]/ );
    }
    return @result;
}

sub notifyUsers {
    my ( $notifyUsers, $subject, $body ) = @_;

    Foswiki::Func::writeDebug("NT = $notifyUsers");
    foreach my $tmp ( @{$notifyUsers} ) {
        Foswiki::Func::writeDebug("MAIL SENT TO $tmp ...");

        my $to    = getUserEmail($tmp);
        my $email = <<"HERE";
From: $sender
To: $to
Subject: $subject
Auto-Submitted: auto-generated
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="------------2D594AE113AD25493C2C7246"

This is a multi-part message in MIME format.
--------------2D594AE113AD25493C2C7246
Content-Type: text/plain; charset=utf-8
Content-Transfer-Encoding: 8bit

$body

--------------2D594AE113AD25493C2C7246--
HERE

        Foswiki::Func::writeDebug("Sending mail to $tmp ...");
        my $error = Foswiki::Func::sendEmail($email);
        if ($error) {
            Foswiki::Func::writeDebug("ERROR WHILE SENDING MAIL - $error");
        }
    }
}

sub getUserEmail {
    my $who    = shift;
    my @emails = Foswiki::Func::wikinameToEmails($who);
    return "" if ( $#emails < 0 );
    Foswiki::Func::writeDebug(
        "- Foswiki::Plugins::${pluginName} USER: $who, EMAIL $emails[0]")
      if $debug;
    return $emails[0];
}

sub addItemToNotifyList {
    my $who     = shift;
    my $what    = shift;
    my $section = shift;
    my $meta    = shift || "";
    my $text    = shift || "";

#Foswiki::Func::writeDebug( "NTF:addItemToNotifyList: adding '$what' to section $sections[$section]" );
    ( $meta, $text ) = checkUserNotifyList($who) if ( $text eq "" );
    return ( $meta, $text )
      if ( isItemInSection( $who, $what, $section, $text ) );
    my @items =
      Foswiki::Plugins::NotificationPlugin::getNotificationsOfUser(
        Foswiki::Func::getWikiName(),
        $section, $text );
    my $newText = "";
    my $tmp     = 0;
    foreach $line ( split( /\n/, $text ) ) {

        #Foswiki::Func::writeDebug( "LINE = $line" );
        $tmp = 0 if ( $line =~ /^---\+\+\s/ && $tmp );
        $tmp = 1 if ( $line =~ /$sections[$section]/ );
        if ( $tmp == 0 ) {
            $newText .= "$line\n";
        }
        if ( $tmp == 1 ) {
            $newText .= "$line\n";
            foreach my $item (@items) {
                $newText .= "   * $item\n";
            }
            $newText .= "   * $what\n";
            $tmp = 2;
            next;
        }
    }
    return ( $meta, $newText );
}

sub removeItemFromNotifyList {
    my $who     = shift;
    my $what    = shift;
    my $section = shift;
    my $meta    = shift || "";
    my $text    = shift || "";

#Foswiki::Func::writeDebug( "NTF:removeItemFromNotifyList: removing '$what' from section $sections[$section]" );
    ( $meta, $text ) = checkUserNotifyList($who) if ( $text eq "" );
    return ( $meta, $text )
      if ( !isItemInSection( $who, $what, $section, $text ) );
    my @items =
      Foswiki::Plugins::NotificationPlugin::getNotificationsOfUser(
        Foswiki::Func::getWikiName(),
        $section, $text );
    my $newText = "";
    my $tmp     = 0;
    foreach $line ( split( /\n/, $text ) ) {
        $tmp = 0 if ( $line =~ /^---\+\+\s/ && $tmp );
        $tmp = 1 if ( $line =~ /$sections[$section]/ );
        if ( $tmp == 0 ) {
            $newText .= "$line\n";
        }
        if ( $tmp == 1 ) {
            $newText .= "$line\n";
            foreach my $item (@items) {

                #Foswiki::Func::writeDebug( "ITEM = ^$item^" );
                $newText .= "   * $item\n" if ( $item ne $what );
            }
            $tmp = 2;
            next;
        }
    }
    return ( $meta, $newText );
}

sub checkUserNotifyList {
    my $who = shift;
    my $tmpText;
    my $tmpMeta;

    #Foswiki::Func::writeDebug( "NTF:checkUserNotifyList: WHO = $who" );
    if (
        !Foswiki::Func::topicExists(
            $Foswiki::cfg{UsersWebName},
            $who . "NotifyList"
        )
      )
    {
        Foswiki::Func::writeDebug("TEST1");
        ( $tmpMeta, $tmpText ) =
          Foswiki::Func::readTopic( $Foswiki::cfg{UsersWebName},
            "NotificationPluginListTemplate" );
        $tmpMeta->put( "TOPICPARENT", { "name" => $who } );
        saveUserNotifyList( $who, $tmpMeta, $tmpText );
    }
    else {
        ( $tmpMeta, $tmpText ) =
          Foswiki::Func::readTopic( $Foswiki::cfg{UsersWebName},
            $who . "NotifyList" );
    }
    return ( $tmpMeta, $tmpText );
}

sub saveUserNotifyList {
    my ( $who, $meta, $text ) = @_;

#Foswiki::Func::writeDebug( "NTF:saveUserNotifyList: Saving Main.".$who."NotifyList topic..." );
    $text =~ s/   /\t/g;

    my $topicObject = Foswiki::Func::saveTopic(
        $Foswiki::cfg{UsersWebName},
        $who . "NotifyList",
        $meta, $text
    );
    if ( !$topicObject ) {
        my $url =
          Foswiki::Func::getOopsUrl( $web, $topic, "oopssaveerr", $error );
        Foswiki::Func::redirectCgiQuery( $query, $url );
    }
}

sub isItemInSection {
    my $who     = shift;
    my $what    = shift;
    my $section = shift;
    my $text    = shift || "";

#Foswiki::Func::writeDebug( "NTF:isItemInSection: WHO = $who, WHT = $what, SCT = $section, TXT = ".length( $text ) );
    my $meta;
    ( $meta, $text ) = checkUserNotifyList($who) if ( $text eq "" );
    my @items = getNotificationsOfUser( $who, $section, $text );
    return 1 if ( grep( /$what/, @items ) );
    return 0;
}

sub showNotifyButtons {
    my $attrs = shift;
    my ( $tin, $win, $tn, $wn, $popup ) = ( "on", "on", "on", "on", "on" );
    my ( $tinOn, $winOn, $tnOn, $wnOn ) = ( "on", "on", "on", "on" );
    my $opt = "";
    my %tmp = ( "on" => "OFF", "off" => "ON" );
    $tin   = $1 if ( $attrs =~ /tin=\"(.*?)\"/ );
    $win   = $1 if ( $attrs =~ /win=\"(.*?)\"/ );
    $tn    = $1 if ( $attrs =~ /tn=\"(.*?)\"/ );
    $wn    = $1 if ( $attrs =~ /wn=\"(.*?)\"/ );
    $popup = $1 if ( $attrs =~ /popup=\"(.*?)\"/ );
    $opt   = $1 if ( $attrs =~ /optional=\"(.*?)\"/ );
    my $text = "";

    my $curWikiName = Foswiki::Func::getWikiName();

    if ( $curWikiName ne "WikiGuest" ) {
        $tinOn = "off"
          if ( !isItemInSection( $curWikiName, "$web.$topic", 0 ) );
        $winOn = "off" if ( !isItemInSection( $curWikiName, "$web", 1 ) );
        $tnOn = "off"
          if ( !isItemInSection( $curWikiName, "$web.$topic", 3 ) );
        $wnOn = "off" if ( !isItemInSection( $curWikiName, "$web", 4 ) );
        $text .=
            "<input onClick='javascript:window.open(\""
          . Foswiki::Func::getScriptUrl( $web, $topic, "changenotify" )
          . "?popup=on\");' type='button' value='Popup'>&nbsp;"
          if ( $popup eq "on" );
        $text .=
            "<input onClick='javascript:location.href(\""
          . Foswiki::Func::getScriptUrl( $web, $topic, "changenotify" )
          . "?what=TIN&action=$tmp{$tinOn}&$opt\");' type='button' value='TIN $tinOn' title='Topic immediate notifications! Click to set it $tmp{$tinOn}!'>&nbsp;"
          if ( $tin eq "on" );
        $text .=
            "<input onClick='javascript:location.href(\""
          . Foswiki::Func::getScriptUrl( $web, $topic, "changenotify" )
          . "?what=WIN&action=$tmp{$winOn}&$opt\");' type='button' value='WIN $winOn' title='Web immediate notifications! Click to set it $tmp{$winOn}!'>&nbsp;"
          if ( $win eq "on" );
        $text .=
            "<input onClick='javascript:location.href(\""
          . Foswiki::Func::getScriptUrl( $web, $topic, "changenotify" )
          . "?what=TN&action=$tmp{$tnOn}&$opt\");' type='button' value='TN $tnOn' title='Topic notifications! Click to set it $tmp{$tnOn}!'>&nbsp;"
          if ( $tn eq "on" );
        $text .=
            "<input onClick='javascript:location.href(\""
          . Foswiki::Func::getScriptUrl( $web, $topic, "changenotify" )
          . "?what=WN&action=$tmp{$wnOn}&$opt\");' type='button' value='WN $wnOn' title='Web notifications! Click to set it $tmp{$wnOn}!'>&nbsp;"
          if ( $wn eq "on" );
    }
    return $text;
}

1;
