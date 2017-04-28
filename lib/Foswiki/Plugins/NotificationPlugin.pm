# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
package Foswiki::Plugins::NotificationPlugin;

use warnings;
use strict;

use Foswiki::Func;
use Foswiki::Time;

our $VERSION = '1.30';
our $RELEASE = '24 Feb 2017';
our $SHORTDESCRIPTION =
  'Send fine grained notifications of topics you are interested in';
our $NO_PREFS_IN_TOPIC = 1;

my @sections = (
    "(Topic) immediate notifications",
    "(Web) immediate notifications",
    "(Regex) immediate notifications",
    "(Topic) notifications",
    "(Web) notifications",
    "(Regex) notifications"
);

my $debug;

# =========================
sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 1 ) {
        Foswiki::Func::writeWarning(
            "Version mismatch between NotificationPlugin and Plugins.pm");
        return 0;
    }

    $debug = $Foswiki::cfg{Plugins}{NotificationPlugin}{Debug} || 0;

    Foswiki::Func::registerRESTHandler(
        'changenotify', \&changenotify_Handler,
        authenticate => 1,  # Set to 0 if handler should be useable by WikiGuest
        validate     => 1,  # Set to 0 to disable StrikeOne CSRF protection
        http_allow => 'POST', # Set to 'GET,POST' to allow use HTTP GET and POST
        description => 'Modify NotificationPlugin subscriptions'
    );

    Foswiki::Func::registerRESTHandler(
        'mailnotify', \&mailnotify_Handler,
        authenticate => 1,  # Set to 0 if handler should be useable by WikiGuest
        validate     => 1,  # Set to 0 to disable StrikeOne CSRF protection
        http_allow => 'POST', # Set to 'GET,POST' to allow use HTTP GET and POST
        description => 'NotificationPlugin mail notificaions'
    );

    Foswiki::Func::registerTagHandler( 'NTF', \&_NTF );

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

    my %seen = ();
    my @unique = grep { !$seen{$_}++ } @notifyUsers;

    Foswiki::Func::writeDebug("COUNT = $#unique") if $debug;
    my $subject = "Topic $_[2].$_[1] has been changed by $wikiUser.";
    my $body =
        "Topic "
      . Foswiki::Func::getScriptUrl( $_[2], $_[1], "view" )
      . " has been changed by $wikiUser at "
      . Foswiki::Func::formatTime( time() ) . " GMT";
    notifyUsers( \@unique, $subject, $body );
}

# =========================
sub getUsers {
    my @result;

    my $it = Foswiki::Func::eachUser();
    while ( $it->hasNext() ) {
        my $tmp = $it->next();
        if (
            Foswiki::Func::topicExists(
                $Foswiki::Cfg{UsersWebName},
                $tmp . 'NotifyList'
            )
          )
        {
            push @result, $tmp;
        }
    }

    #print STDERR Data::Dumper::Dumper( \@result );
    return @result;
}

sub getUsersToNotify {
    my ( $tweb, $ttopic, $section ) = @_;
    my @result;

    my $it = Foswiki::Func::eachUser();
    while ( $it->hasNext() ) {
        my $tmp = $it->next();
        next
          unless (
            Foswiki::Func::topicExists(
                $Foswiki::Cfg{UsersWebName},
                $tmp . 'NotifyList'
            )
          );

        # Don't notify if the user cannot view the topic.
        next
          unless (
            Foswiki::Func::checkAccessPermission(
                'VIEW', $tmp, undef, $ttopic, $tweb
            )
          );

       # Access permissions are NOT checked for the *NotifyList topic.
       # The current user saving the topic doesn't necessarily have view access.
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

    #print STDERR "Notify scheduled for: " . Data::Dumper::Dumper( \@result );
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

    my $sender = $Foswiki::cfg{Email}{WikiAgentEmail}
      || $Foswiki::cfg{WebMasterEmail};

    Foswiki::Func::writeDebug( "NT = " . join( ',', $notifyUsers ) ) if $debug;
    foreach my $tmp ( @{$notifyUsers} ) {
        Foswiki::Func::writeDebug("MAIL SENT TO $tmp ...") if $debug;

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

        Foswiki::Func::writeDebug("Sending mail to $tmp ...") if $debug;

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
    my $meta    = shift;
    my $text    = shift;

#Foswiki::Func::writeDebug( "NTF:addItemToNotifyList: adding '$what' to section $sections[$section]" );
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
    my $meta    = shift;
    my $text    = shift;

#Foswiki::Func::writeDebug( "NTF:removeItemFromNotifyList: removing '$what' from section $sections[$section]" );
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

    #print STDERR "NTF:checkUserNotifyList: WHO = $who\n";
    if (
        Foswiki::Func::topicExists(
            $Foswiki::cfg{UsersWebName},
            $who . "NotifyList"
        )
      )
    {
        ( $tmpMeta, $tmpText ) =
          Foswiki::Func::readTopic( $Foswiki::cfg{UsersWebName},
            $who . "NotifyList" );
    }

    unless ($tmpText) {
        ( $tmpMeta, $tmpText ) =
          Foswiki::Func::readTopic( $Foswiki::cfg{UsersWebName},
            "NotificationPluginListTemplate" );
        $tmpMeta->put( "TOPICPARENT", { "name" => $who } );
        saveUserNotifyList( $who, $tmpMeta, $tmpText );
    }

    return ( $tmpMeta, $tmpText );
}

sub saveUserNotifyList {
    my ( $who, $meta, $text ) = @_;

#Foswiki::Func::writeDebug( "NTF:saveUserNotifyList: Saving Main.".$who."NotifyList topic...".$text );

    my $topicObject = Foswiki::Func::saveTopic(
        $Foswiki::cfg{UsersWebName},
        $who . "NotifyList",
        $meta, $text
    );
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
    my ( $tin, $win, $tn, $wn, $popup ) = ( "on", "on", "on", "on", "off" );
    my ( $tinOn, $winOn, $tnOn, $wnOn ) = ( "on", "on", "on", "on" );
    my %tmp = ( "on" => "OFF", "off" => "ON" );
    $popup = $params->{popup} || "off";
    my $def = ( $popup eq 'on' ) ? 'off' : 'on';
    $tin = $params->{tin} || $def;
    $win = $params->{win} || $def;
    $tn  = $params->{tn}  || $def;
    $wn  = $params->{wn}  || $def;

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

        if ( $popup eq 'on' ) {
            my $tinC = ( $tinOn eq 'on' ) ? 'checked' : '';
            my $winC = ( $winOn eq 'on' ) ? 'checked' : '';
            my $tnC  = ( $tnOn  eq 'on' ) ? 'checked' : '';
            my $wnC  = ( $wnOn  eq 'on' ) ? 'checked' : '';
            $text .= <<HERE;
            %JQREQUIRE{"ui::dialog"}%
           <a href="%SCRIPTURLPATH{view}%/%SYSTEMWEB%/NotificationPlugin?skin=text;section=notification;TIN=$tinC;WIN=$winC;WN=$wnC;TN=$tnC;notifyweb=%WEB%;notifytopic=%TOPIC%" alt="Update..." title="Update" class="jqUIDialogLink {cache:false}">Notifications</a>
HERE
        }

        $text .= <<"HERE" if $tin eq 'on';
            <form id="TIN" action="$restURL" method="post">
                <input type="hidden" name="what" value="TIN" />
                <input type="hidden" name="topic" value="$web.$topic" />
                <input type="hidden" name="action" value="$tmp{$tinOn}" />
                <input type="submit" class="foswikiButton" value="TIN $tinOn" title="Topic immediate notifications! Click to set it $tmp{$tinOn}!" />
            </form>
HERE
        $text .= <<"HERE" if $win eq 'on';
            <form id="WIN" action="$restURL" method="post">
                <input type="hidden" name="what" value="WIN" />
                <input type="hidden" name="topic" value="$web.$topic" />
                <input type="hidden" name="action" value="$tmp{$winOn}" />
                <input type="submit" class="foswikiButton" value="WIN $winOn" title="Topic immediate notifications! Click to set it $tmp{$winOn}!" />
            </form>
HERE

        $text .= <<"HERE" if $tn eq 'on';
            <form id="TN" action="$restURL" method="post">
                <input type="hidden" name="what" value="TN" />
                <input type="hidden" name="topic" value="$web.$topic" />
                <input type="hidden" name="action" value="$tmp{$tnOn}" />
                <input type="submit" class="foswikiButton" value="TN $tnOn" title="Topic immediate notifications! Click to set it $tmp{$tnOn}!" />
            </form>
HERE

        $text .= <<"HERE" if $wn eq 'on';
            <form id="WN" action="$restURL" method="post">
                <input type="hidden" name="what" value="WN" />
                <input type="hidden" name="topic" value="$web.$topic" />
                <input type="hidden" name="action" value="$tmp{$wnOn}" />
                <input type="submit" class="foswikiButton" value="WN $wnOn" title="Topic immediate notifications! Click to set it $tmp{$wnOn}!" />
            </form>
HERE

    }
    return $text;
}

sub changenotify_Handler {

    my ( $session, $subject, $verb, $response ) = @_;

    my $web   = $session->{webName};
    my $topic = $session->{topicName};

    my $query         = Foswiki::Func::getCgiQuery();
    my $wikiName      = Foswiki::Func::getWikiName();
    my $scriptUrlPath = Foswiki::Func::getScriptUrlPath( $web, $topic, 'view' );

    my $action = $query->param("action");
    my $what   = $query->param("what");

    if ( $wikiName ne "WikiGuest" ) {
        my ( $meta, $text ) = checkUserNotifyList($wikiName);

        if ($action) {
            if ($what) {
                ( $meta, $text ) =
                  modify_notification( $meta, $text, $web, $topic, $what,
                    $action );
            }
            else {
                # loop thru all possible checkboxes
                for (qw(TIN WIN TN WN)) {
                    ( $meta, $text ) =
                      modify_notification( $meta, $text, $web, $topic, $_,
                        scalar $query->param($_) );
                }
            }
        }
        Foswiki::Plugins::NotificationPlugin::saveUserNotifyList( $wikiName,
            $meta, $text );

        Foswiki::Func::writeDebug("URL = $scriptUrlPath") if $debug;
        Foswiki::Func::redirectCgiQuery( $query, $scriptUrlPath );
    }

}

sub modify_notification {
    my ( $meta, $text, $webName, $topic, $what, $action ) = @_;
    $action ||= '';

    Foswiki::Func::writeDebug("ModifyNotiication entered - ($what), ($action)")
      if $debug;

    my %tmp = ( "TIN" => 0, "WIN" => 1, "TN" => 3, "WN" => 4 );

    my $str = "$webName.$topic";
    $str = "$webName" if ( $tmp{$what} == 1 || $tmp{$what} == 4 );
    Foswiki::Func::writeDebug("WHAT = $what") if $debug;
    Foswiki::Func::writeDebug("STR = $str")   if $debug;
    my $wikiName = Foswiki::Func::getWikiName;

    if ( $action eq "ON" ) {
        ( $meta, $text ) =
          Foswiki::Plugins::NotificationPlugin::addItemToNotifyList( $wikiName,
            $str, $tmp{$what}, $meta, $text );
    }
    else {
        ( $meta, $text ) =
          Foswiki::Plugins::NotificationPlugin::removeItemFromNotifyList(
            $wikiName, $str, $tmp{$what}, $meta, $text );
    }

    return ( $meta, $text );
}

sub mailnotify_Handler {

    my ( $session, $subject, $verb, $response ) = @_;

    my $web   = $session->{webName};
    my $topic = $session->{topicName};

    my $query         = Foswiki::Func::getCgiQuery();
    my $wikiName      = Foswiki::Func::getWikiName();
    my $scriptUrlPath = Foswiki::Func::getScriptUrlPath( $web, $topic, 'view' );

    my $quiet = $query->param('q');

    $debug = '0' if $quiet;

    &Foswiki::Func::writeDebug("START REGULAR NOTIFICATIONS");
    &Foswiki::Func::writeDebug("===========================");
    $debug && print "Foswiki mail notification\n";
    $debug && print "- to suppress all normal output: mailnotify -q\n";
    my @users = getUsers();

    my %notify;
    foreach my $user (@users) {
        $notify{$user}{"web"} = join(
            ",",
            &Foswiki::Plugins::NotificationPlugin::getNotificationsOfUser(
                $user, 4
            )
        );
        $notify{$user}{"topic"} = join(
            ",",
            &Foswiki::Plugins::NotificationPlugin::getNotificationsOfUser(
                $user, 3
            )
        );
        $notify{$user}{"regex"} = join(
            ",",
            &Foswiki::Plugins::NotificationPlugin::getNotificationsOfUser(
                $user, 5
            )
        );
    }

    #print STDERR Data::Dumper::Dumper( \%notify );

    my @allChanges;
    my %lastmodify;

    # Build a list of unique topics that have been changed.
    foreach my $web ( Foswiki::Func::getListOfWebs('user') ) {

        $lastmodify{$web} = 0;
        my $currmodify = 0;
        my %exclude;

        my $it = Foswiki::Func::eachChangeSince( $web, $lastmodify{$web} + 1 );
        while ( $it->hasNext() ) {
            my $change = $it->next();
            next if $change->{minor};
            next if $change->{more} && $change->{more} =~ m/minor/;

            next unless Foswiki::Func::topicExists( $web, $change->{topic} );

            next if ( $exclude{"$web.$change->{topic}"} );

            $currmodify = $change->{time} if ( $change->{time} > $currmodify );
            $exclude{"$web.$change->{topic}"} = 1;
            $change->{web} = $web;
            push @allChanges, $change;
        }

        # save date of the last modification
        #&Foswiki::Store::saveFile( "$dataDir/$web/.mailnotify", $currmodify );
    }

    #print STDERR Data::Dumper::Dumper( \@allChanges );
    my $skin = Foswiki::Func::getPreferencesValue("SKIN");
    my $htmlTmpl = Foswiki::Func::readTemplate( "htmlchanges", $skin );

    my ( $htmlBefore, $htmlWebTmpl, $htmlTopicTmpl, $htmlAfter ) =
      split( /%REPEAT%/, $htmlTmpl );

    #print STDERR "BEFORE = $htmlBefore\n";
    #print STDERR "HTML = $htmlTmpl\n";
    #print STDERR "AFTER = $htmlAfter\n";

    my $htmlEmailTmpl = Foswiki::Func::renderText($htmlBefore);
    $htmlAfter = Foswiki::Func::renderText($htmlAfter);

    my $from = &Foswiki::Func::getPreferencesValue("WIKIWEBMASTER");

    foreach my $user (@users) {
        my $htmlEmailBody = $htmlEmailTmpl;
        $htmlEmailBody =~ s/%WIKIUSER%/$user/g;
        my $topiclist     = "";
        my $htmltopiclist = "";
        my $htmlregexlist = "";
        my $newText;
        my %handled;
        my $count = 0;

        foreach my $change (@allChanges) {
            my $web        = $change->{web};
            my $topicName  = $change->{topic};
            my $userName   = $change->{cuid};
            my $changeTime = $change->{time};
            my $revision   = $change->{revision};

            my $wikiuser = &Foswiki::Func::userToWikiName( $userName, 1 );

            #print STDERR "Checking VIEW for $web.$topicName by $user\n";
            next
              unless (
                Foswiki::Func::checkAccessPermission(
                    'VIEW', $user, undef, $topicName, $web
                )
              );

            foreach my $tweb ( split( /,/, $notify{$user}{"web"} ) ) {

                #print STDERR " NOTIFY WEB !$web!, !$tweb!\n";
                if ( $web eq $tweb ) {

                    #print "HOP\n";
                    if ( !$handled{$tweb} ) {
                        $newText = $htmlWebTmpl;
                        $newText =~ s/%WEBNAME%/$web/g;
                        $newText = Foswiki::Func::renderText($newText);
                        $htmlEmailBody .= $newText;
                        $handled{$tweb} = 1;
                    }

    # new HTML text for web
    #print "WEB = $web, TOP = $topicName, USER = $userName, WIKI = $wikiuser\n";
                    $newText = $htmlTopicTmpl;
                    $newText =~ s/%TOPICNAME%/$topicName/g;
                    $newText =~ s/%WEBNAME%/$web/g;
                    $newText =~ s/%AUTHOR%/$wikiuser/g;
                    $newText =~ s/%LOCKED%//g;
                    my $time = Foswiki::Time::formatTime($changeTime);
                    $newText =~ s/%TIME%/$time/g;
                    $newText =~ s/%REVISION%/1\.$revision/g;
                    $newText = Foswiki::Func::renderText($newText);

                    my $head =
                      Foswiki::Func::summariseChanges( $web, $topicName );

                    $newText =~ s/%TEXTHEAD%/$head/g;
                    $htmlEmailBody .= $newText;

                    # new plain text for web
                    $count++;
                }
            }
            foreach my $ttopic ( split( /,/, $notify{$user}{"topic"} ) ) {
                ( my $tweb, $ttopic ) =
                  Foswiki::Func::normalizeWebTopicName( '', $ttopic );
                if ( "$web.$topicName" eq "$tweb.$ttopic" ) {

                    #print STDERR "NOTIFY TOPIC !$tweb!, !$ttopic!\n";
                    $newText = $htmlTopicTmpl;
                    $newText =~ s/%TOPICNAME%/$topicName/g;
                    $newText =~ s/%WEBNAME%/$web/g;
                    $newText =~ s/%AUTHOR%/$wikiuser/g;
                    $newText =~ s/%LOCKED%//g;
                    my $time = Foswiki::Time::formatTime($changeTime);
                    $newText =~ s/%TIME%/$time/g;
                    $newText =~ s/%REVISION%/1\.$revision/g;
                    $newText = Foswiki::Func::renderText($newText);
                    my $head =
                      Foswiki::Func::summariseChanges( $web, $topicName );

                    #print STDERR "CHANGES: $head\n";
                    $newText =~ s/%TEXTHEAD%/$head/g;
                    $htmltopiclist .= $newText;

#print STDERR "===============================\n$newText\n=====================\n";
                    $count++;
                }
            }
            foreach my $tregex ( split( /,/, $notify{$user}{"regex"} ) ) {

                #print STDERR "NOTIFY REGEX !$web!, !$tregex!\n";
                if ( "$web.$topicName" =~ /$tregex/ ) {
                    $newText = $htmlTopicTmpl;
                    $newText =~ s/%TOPICNAME%/$topicName/g;
                    $newText =~ s/%WEBNAME%/$web/g;
                    $newText =~ s/%AUTHOR%/$wikiuser/g;
                    $newText =~ s/%LOCKED%//g;
                    my $time = Foswiki::Time::formatTime($changeTime);
                    $newText =~ s/%TIME%/$time/g;
                    $newText =~ s/%REVISION%/1\.$revision/g;
                    $newText = Foswiki::Func::renderText($newText);
                    my $head =
                      Foswiki::Func::summariseChanges( $web, $topicName );
                    $newText =~ s/%TEXTHEAD%/$head/g;
                    $htmlregexlist .= $newText;
                    $count++;
                }
            }
        }

        #print "COUNT = $count\n";
        if ( $count > 0 ) {
            $htmlEmailBody .= $htmlAfter;
            $htmlEmailBody =~ s/%TOPICLIST%/$htmltopiclist/goi;
            $htmlEmailBody =~ s/%REGEXLIST%/$htmlregexlist/goi;

#print "HTML EMAIL BODY = \n==================================\n$htmlEmailBody\n===============================\n";

            Foswiki::Func::readTemplate( "mailnotify", $skin );

            my $email =
              Foswiki::Func::expandCommonVariables(
                Foswiki::Func::expandTemplate('MailNotifyBody'),
                $Foswiki::cfg{HomeTopicName}, $web );

            #print STDERR "MAILNOTIFYBODY: ($email)\n";

            if ( $Foswiki::cfg{MailerContrib}{RemoveImgInMailnotify} ) {

                # change images to [alt] text if there, else remove image
                $email =~ s/<img\s[^>]*\balt=\"([^\"]+)[^>]*>/[$1]/gi;
                $email =~ s/<img\s[^>]*\bsrc=.*?[^>]>//gi;
            }

            $email =~ s/%EMAILFROM%/$from/go;
            my $mail =
              &Foswiki::Plugins::NotificationPlugin::getUserEmail($user);

            #print "USER = $user, EMAIL = $mail";
            $email =~ s/%EMAILTO%/$mail/go;
            $email =~ s/%HTML_TEXT%/$htmlEmailBody/go;
            $email = Foswiki::Func::expandCommonVariables( $email, $topic );

            #print STDERR "MAILNOTIFYBODY-Tailored: ($email)\n";

            # change absolute addresses to relative ones & do some cleanup
            $email =~ s/(href=\")$scriptUrlPath/$1..\/../goi;
            $email =~ s/(action=\")$scriptUrlPath/$1..\/../goi;
            $email =~ s|( ?) *</*nop/*>\n?|$1|gois;

            $debug && print "- Sending mail notification to $user\n";
            &Foswiki::Func::writeDebug("MAIL SENT TO $user ...");

            #print STDERR "=============\n($email)\n===========\n";
            #
            #$email = Foswiki::encode_utf8( $email );

            my $error = &Foswiki::Func::sendEmail($email);
            if ($error) {
                &Foswiki::Func::writeDebug("ERROR IN SENDING MAIL - $error");
                print STDERR "* $error\n";
            }
        }
    }

    &Foswiki::Func::writeDebug("FINISH REGULAR NOTIFICATIONS");
    &Foswiki::Func::writeDebug("============================");
    $debug && print "End Foswiki mail notification\n";

}

1;
