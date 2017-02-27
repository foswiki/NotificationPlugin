# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
package Foswiki::Plugins::NotificationPlugin;

use warnings;
use strict;

our $VERSION = '1.30';
our $RELEASE = '24 Feb 2017';
our $SHORTDESCRIPTION =
  'Send fine grained notifications of topics you are interested in';

my @sections = (
    "(Topic) immediate notifications",
    "(Web) immediate notifications",
    "(Regex) immediate notifications",
    "(Topic) notifications",
    "(Web) notifications",
    "(Regex) notifications"
);

my @users;
my $debug;
my $sender;

# =========================
sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 1 ) {
        Foswiki::Func::writeWarning(
            "Version mismatch between NotificationPlugin and Plugins.pm");
        return 0;
    }

    @users = getUsers();

    $debug = $Foswiki::cfg{Plugins}{NotificationPlugin}{Debug} || 0;

    Foswiki::Func::registerRESTHandler(
        'changenotify', \&restHandler,
        authenticate => 1,  # Set to 0 if handler should be useable by WikiGuest
        validate     => 0,  # Set to 0 to disable StrikeOne CSRF protection
        http_allow => 'POST', # Set to 'GET,POST' to allow use HTTP GET and POST
        description => 'Modify NotificationPlugin subscriptions'
    );

    Foswiki::Func::registerTagHandler( 'NTF', \&_NTF );

# KISS:
# $sender = $Foswiki::cfg{Plugins}{NotificationPlugin}{SENDER} || "Foswiki NotificationPlugin";
    $sender = $Foswiki::cfg{WebMasterEmail};

    # Plugin correctly initialized
    Foswiki::Func::writeDebug(
"- Foswiki::Plugins::NotificationPlugin::initPlugin( $web.$topic ) is OK"
    ) if $debug;
    return 1;
}

sub _NTF {

    return showNotifyButtons( $_[1] );
}

# =========================
sub beforeSaveHandler {
    ### my ( $text, $topic, $web ) = @_;

    Foswiki::Func::writeDebug(
        "- NotificatinoPlugin::beforeSaveHandler( $_[2].$_[1] )")
      if $debug;

    my $wikiUser = Foswiki::Func::getWikiName();

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

# Consider %SEARCH{"notifications" type="literal" topic="*NotifyList" web="Usersweb" format="$topic" separator="," nonoise="on"}%
    my @topics = Foswiki::Func::getTopicList( $Foswiki::cfg{UsersWebName} );

    foreach my $name (@topics) {
        next unless $name =~ /^(.*)NotifyList$/;

        Foswiki::Func::writeDebug("NAME = $1");
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
    my $test = "";
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
        "- Foswiki::Plugins::NotificationPlugin USER: $who, EMAIL $emails[0]")
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
    foreach my $line ( split( /\n/, $text ) ) {

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
    foreach my $line ( split( /\n/, $text ) ) {
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

    my $topicObject = Foswiki::Func::saveTopic(
        $Foswiki::cfg{UsersWebName},
        $who . "NotifyList",
        $meta, $text
    );
    if ( !$topicObject ) {

     #my $url =
     #  Foswiki::Func::getOopsUrl( $web, $topic, "oopssaveerr", 'save failed' );
     #Foswiki::Func::redirectCgiQuery( $query, $url );
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
    my $params = shift;
    my ( $tin, $win, $tn, $wn, $popup ) = ( "on", "on", "on", "on", "on" );
    my ( $tinOn, $winOn, $tnOn, $wnOn ) = ( "on", "on", "on", "on" );
    my %tmp = ( "on" => "OFF", "off" => "ON" );
    $tin = $params->{tin} || "on";
    $win = $params->{win} || "on";
    $tn  = $params->{tn}  || "on";
    $wn  = $params->{wn}  || "on";

    #$popup = $1 if ( $attrs =~ /popup=\"(.*?)\"/ );
    my $text = "";

    my $curWikiName = Foswiki::Func::getWikiName();
    my $web         = $Foswiki::Plugins::SESSION->{webName};
    my $topic       = $Foswiki::Plugins::SESSION->{topicName};
    my $restURL     = Foswiki::Func::getScriptUrl( undef, undef, 'rest' )
      . '/NotificationPlugin/changenotify';

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
        $text .= <<"HERE" if $tin eq 'on';
            <form id="TIN" action="$restURL" method="post">
                <input type="hidden" name="what" value="TIN" />
                <input type="hidden" name="topic" value="$web.$topic" />
                <input type="hidden" name="action" value="$tmp{$tinOn}" />
                <input  href="#" type="button" onclick="document.getElementById('TIN').submit();" value="TIN $tinOn" title="Topic immediate notifications! Click to set it $tmp{$tinOn}!" />
            </form>
HERE
        $text .= <<"HERE" if $win eq 'on';
            <form id="WIN" action="$restURL" method="post">
                <input type="hidden" name="what" value="WIN" />
                <input type="hidden" name="topic" value="$web.$topic" />
                <input type="hidden" name="action" value="$tmp{$winOn}" />
                <input  href="#" type="button" onclick="document.getElementById('WIN').submit();" value="WIN $winOn" title="Topic immediate notifications! Click to set it $tmp{$winOn}!" />
            </form>
HERE

        $text .= <<"HERE" if $tn eq 'on';
            <form id="TN" action="$restURL" method="post">
                <input type="hidden" name="what" value="TN" />
                <input type="hidden" name="topic" value="$web.$topic" />
                <input type="hidden" name="action" value="$tmp{$tnOn}" />
                <input  href="#" type="button" onclick="document.getElementById('TN').submit();" value="TN $tnOn" title="Topic immediate notifications! Click to set it $tmp{$tnOn}!" />
            </form>
HERE

        $text .= <<"HERE" if $wn eq 'on';
            <form id="WN" action="$restURL" method="post">
                <input type="hidden" name="what" value="WN" />
                <input type="hidden" name="topic" value="$web.$topic" />
                <input type="hidden" name="action" value="$tmp{$wnOn}" />
                <input  href="#" type="button" onclick="document.getElementById('WN').submit();" value="WN $wnOn" title="Topic immediate notifications! Click to set it $tmp{$wnOn}!" />
            </form>
HERE

    }
    return $text;
}

sub restHandler {

    my ( $session, $subject, $verb, $response ) = @_;

    my $web   = $session->{webName};
    my $topic = $session->{topicName};

  #
  #   # Use return to have foswiki manage the output
  #   return "This is an example of a REST invocation\n\n";
  #
  #   # To completely control the output from the handler:
  #   $response->headers()   - output headers, which must be utf-8 encoded
  #   $response->body()      - output binary data that should not be encoded.
  #   $response->print()     - output unicode text.
  #   # Note that print() and body() may not be combined.  Use one or the other.

    my $query         = Foswiki::Func::getCgiQuery();
    my $wikiName      = Foswiki::Func::getWikiName();
    my $scriptUrlPath = Foswiki::Func::getScriptUrlPath('view');

    my $action = $query->param("action");
    my $what   = $query->param("what");

    if ( $wikiName ne "WikiGuest" ) {
        if ($action) {
            if ($what) {
                modify_notification( $web, $topic, $what, $action );
            }
            else {
                # loop thru all possible checkboxes
                for (qw(TIN WIN TN WN)) {
                    modify_notification( $web,
                        $topic, $_, scalar $query->param($_) );
                }
            }
        }

        # All work is done; redirect if needed
        unless ( scalar $query->param("popup") ) {
            Foswiki::Func::writeDebug("URL = $scriptUrlPath/$web/$topic");
            Foswiki::Func::redirectCgiQuery( $query,
                $scriptUrlPath . "/$web/$topic" );
        }
    }

    #  Fallthru: do something if no Javascript
    return draw_checkboxes( $scriptUrlPath, $topic, $web );
}

sub modify_notification {
    my ( $webName, $topic, $what, $action ) = @_;
    $action ||= '';

    Foswiki::Func::writeDebug("ModifyNotiication entered - ($what), ($action)");

    my %tmp = ( "TIN" => 0, "WIN" => 1, "TN" => 3, "WN" => 4 );

    my $str = "$webName.$topic";
    $str = "$webName" if ( $tmp{$what} == 1 || $tmp{$what} == 4 );
    Foswiki::Func::writeDebug("WHAT = $what");
    Foswiki::Func::writeDebug("STR = $str");
    my ( $meta, $text ) = ( "", "" );
    my $wikiName = Foswiki::Func::getWikiName;

    if ( $action eq "ON" ) {
        ( $meta, $text ) =
          Foswiki::Plugins::NotificationPlugin::addItemToNotifyList( $wikiName,
            $str, $tmp{$what} );
    }
    else {
        ( $meta, $text ) =
          Foswiki::Plugins::NotificationPlugin::removeItemFromNotifyList(
            $wikiName, $str, $tmp{$what} );
    }
    Foswiki::Plugins::NotificationPlugin::saveUserNotifyList( $wikiName, $meta,
        $text );
}

sub draw_checkboxes {
    my ( $scriptUrlPath, $topic, $webName ) = @_;

    my $wikiName = Foswiki::Func::getWikiName();

    my $tinOn =
      Foswiki::Plugins::NotificationPlugin::isItemInSection( $wikiName,
        "$webName.$topic", 0 );
    my $winOn =
      Foswiki::Plugins::NotificationPlugin::isItemInSection( $wikiName,
        "$webName", 1 );
    my $tnOn = Foswiki::Plugins::NotificationPlugin::isItemInSection( $wikiName,
        "$webName.$topic", 3 );
    my $wnOn = Foswiki::Plugins::NotificationPlugin::isItemInSection( $wikiName,
        "$webName", 4 );
    my $action = $scriptUrlPath . "/changenotify/" . $webName . "/" . $topic;
    my $html =
qq!<form onSubmit="setTimeout('window.close()',2000)" method="post" action="$action">
    <input type="hidden" name="popup" value="1" />
    <input type="checkbox" name="TIN" value="ON">Immediate Notification of changes to <b>$topic</b><br>
    <input type="checkbox" name="WIN" value="ON">Immediate Notification of changes to <b>$webName</b><br>
    <input type="checkbox" name="TN" value="ON" >Normal Notification of changes to <b>$topic</b><br>
    <input type="checkbox" name="WN" value="ON" >Normal Notification of changes to <b>$webName</b><br>
    <input type="submit" value="Update" name="action"></form>!;
    $html =~ s/(name="TIN")/$1 checked="checked"/ if $tinOn;
    $html =~ s/(name="WIN")/$1 checked="checked"/ if $winOn;
    $html =~ s/(name="TN")/$1 checked="checked"/  if $tnOn;
    $html =~ s/(name="WN")/$1 checked="checked"/  if $wnOn;
    return $html;
}
1;
