# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2000-2003 Andrea Sterbini, a.sterbini@flashnet.it
# Copyright (C) 2001-2003 Peter Thoeny, peter@thoeny.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at 
# http://www.gnu.org/copyleft/gpl.html
#
# =========================
#
# This is an empty Foswiki plugin. Use it as a template
# for your own plugins; see %SYSTEMWEB%.Plugins for details.
#
# Each plugin is a package that may contain these functions:        VERSION:
#
#   initPlugin              ( $topic, $web, $user, $installWeb )    1.000
#   initializeUserHandler   ( $loginName, $url, $pathInfo )         1.010
#   registrationHandler     ( $web, $wikiName, $loginName )         1.010
#   commonTagsHandler       ( $text, $topic, $web )                 1.000
#   startRenderingHandler   ( $text, $web )                         1.000
#   outsidePREHandler       ( $text )                               1.000
#   insidePREHandler        ( $text )                               1.000
#   endRenderingHandler     ( $text )                               1.000
#   beforeEditHandler       ( $text, $topic, $web )                 1.010
#   afterEditHandler        ( $text, $topic, $web )                 1.010
#   beforeSaveHandler       ( $text, $topic, $web )                 1.010
#   writeHeaderHandler      ( $query )                              1.010  Use only in one Plugin
#   redirectCgiQueryHandler ( $query, $url )                        1.010  Use only in one Plugin
#   getSessionValueHandler  ( $key )                                1.010  Use only in one Plugin
#   setSessionValueHandler  ( $key, $value )                        1.010  Use only in one Plugin
#
# initPlugin is required, all other are optional. 
# For increased performance, all handlers except initPlugin are
# disabled. To enable a handler remove the leading DISABLE_ from
# the function name. Remove disabled handlers you do not need.
#
# NOTE: To interact with Foswiki use the official Foswiki functions 
# in the Foswiki::Func module. Do not reference any functions or
# variables elsewhere in Foswiki!!


# =========================
package Foswiki::Plugins::NotificationPlugin;    # change the package name and $pluginName!!!

use Foswiki::Store;

# =========================
use vars qw(
        $web $topic $user $installWeb $VERSION $RELEASE $pluginName
        $sender @users $debug @sections
    );

# This should always be $Rev$ so that Foswiki can determine the checked-in
# status of the plugin. It is used by the build automation tools, so
# you should leave it alone.
$VERSION = '$Rev$';

# This is a free-form string you can use to "name" your own plugin version.
# It is *not* used by the build automation tools, but is reported as part
# of the version number in PLUGINDESCRIPTIONS.
$RELEASE = 'Dakar';

$pluginName = 'NotificationPlugin';  # Name of this Plugin

# =========================
sub initPlugin
{
    ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if( $Foswiki::Plugins::VERSION < 1 ) {
        Foswiki::Func::writeWarning( "Version mismatch between $pluginName and Plugins.pm" );
        return 0;
    }

    @users = getUsers();
    @sections = (
      "(Topic) immediate notifications",
      "(Web) immediate notifications",
      "(Regex) immediate notifications",
      "(Topic) notifications",
      "(Web) notifications",
      "(Regex) notifications"
    );
    
    $debug = Foswiki::Func::getPreferencesFlag( "\U$pluginName\E_DEBUG" ) || 0;
    $sender = Foswiki::Func::getPreferencesValue( "\U$pluginName\E_SENDER" ) || "Foswiki NotificationPlugin";
    
    # Plugin correctly initialized
    Foswiki::Func::writeDebug( "- Foswiki::Plugins::${pluginName}::initPlugin( $web.$topic ) is OK" ) if $debug;
    return 1;
}

# =========================
sub commonTagsHandler
{
### my ( $text, $topic, $web ) = @_;   # do not uncomment, use $_[0], $_[1]... instead

    Foswiki::Func::writeDebug( "- ${pluginName}::commonTagsHandler( $_[2].$_[1] )" ) if $debug;

    # This is the place to define customized tags and variables
    # Called by sub handleCommonTags, after %INCLUDE:"..."%

    # do custom extension rule, like for example:
    $_[0] =~ s/%NTF{(.*?)}%/&showNotifyButtons($1)/ge;
}

# =========================
sub beforeSaveHandler
{
### my ( $text, $topic, $web ) = @_;   # do not uncomment, use $_[0], $_[1]... instead

  Foswiki::Func::writeDebug( "- ${pluginName}::beforeSaveHandler( $_[2].$_[1] )" ) if $debug;

  # This handler is called by Foswiki::Store::saveTopic just before the save action.
  # New hook in Foswiki::Plugins $VERSION = '1.010'

  my $wikiUser = &Foswiki::Func::userToWikiName( $user, 1 );
  my @notifyUsers = ();
  push( @notifyUsers, getUsersToNotify( $_[2], $_[1], 0 ) );
  push( @notifyUsers, getUsersToNotify( $_[2], $_[1], 1 ) );
  push( @notifyUsers, getUsersToNotify( $_[2], $_[1], 2 ) );
  #&Foswiki::Func::writeDebug( "COUNT = $#notifyUsers" );
  my $subject = "Topic $_[2].$_[1] has been changed by $wikiUser.";
  my $body = "Topic ".&Foswiki::Func::getScriptUrl( $_[2], $_[1], "view" )." has been changed by $wikiUser at " . &Foswiki::Func::formatTime( time() ) . " GMT";
  notifyUsers( \@notifyUsers, $subject, $body );
}

# =========================
sub getUsers {
  my @result;
  #&Foswiki::Func::writeDebug( &Foswiki::Func::getDataDir()."/".&Foswiki::Func::getMainWebname() );
  if ( opendir( DIR, &Foswiki::Func::getDataDir()."/".&Foswiki::Func::getMainWebname() ) ) {
    my @topics = grep( /NotifyList.*txt$/, readdir( DIR ) );
    foreach my $name ( @topics ) {
      $name =~ /^(.*?)NotifyList/;
      #&Foswiki::Func::writeDebug( "NAME = $1" );
      $result[++$#result] = $1 if ( $1 ne "" ); 
    }
    closedir( DIR );
  }
  #&Foswiki::Func::writeDebug( "USERS = $#result" );
  return @result;
}

sub getUsersToNotify {
  my ( $tweb, $ttopic, $section ) = @_;
  my @result;
  #&Foswiki::Func::writeDebug( "TYPE = $type" );
  foreach my $tmp ( @users ) {
    #&Foswiki::Func::writeDebug( "TMP = $tmp" );
    my $text = &Foswiki::Func::readTopic( &Foswiki::Func::getMainWebname(), "$tmp"."NotifyList" );
    my $test = "";
    foreach my $line ( split( /\n/, $text ) ) {
      $line =~ s/\s+$//;
      #&Foswiki::Func::writeDebug( "LINE = $line" );
      #&Foswiki::Func::writeDebug( "TEST = $test" );
      $test = "" if ( ( $test ne "" ) && ( $line !~ /^\s*\*/ ) );
      #&Foswiki::Func::writeDebug( "TEST = $test" );
      if ( $test eq "Topic" ) {
        $line =~ /\s*\*\s(.*?)\.(.*)/;
        if ( ( $tweb eq $1 ) && ( $ttopic eq $2 ) ) {
          $result[++$#result] = $tmp;
          last;
        }
      } elsif ( $test eq "Web" ) {
        $line =~ /\s*\*\s(.*)/;
        if ( $tweb eq $1 ) {
          $result[++$#result] = $tmp;
          last;
        }
      } elsif ( $test eq "Regex" ) {
        $line =~ /\s*\*\s(.*)/;
        if ( "$tweb.$ttopic" =~ /$1/ ) {
          $result[++$#result] = $tmp;
          last;
      }
      }
      $test = $1 if ( $line =~ /$sections[$section]/ );
    }
  }  
  return @result;
}

sub getNotificationsOfUser {
  my $who = shift;
  my $section = shift;
  my $text = shift || "";
  my $meta;
  #&Foswiki::Func::writeDebug( "NTF:getNotificationsOfUser: WHO = $who, SCT = $section, TXT = ".length( $text ) );
  ( $meta, $text ) = checkUserNotifyList( $who ) if ( $text eq "" );
  my @result;
  #&Foswiki::Func::writeDebug( "USER = $tuser" );
  $test = "";
  foreach my $line ( split( /\n/, $text ) ) {
      #&Foswiki::Func::writeDebug( "LINE = $line" );
    while ( ( $line =~ /\n$/ ) || ( $line =~ /\r$/ ) ) {
      chop( $line );
    }
    last if ( ( $test ne "" ) && ( $line !~ /^\s*\*/ ) );
    if ( $test eq "Topic" ) {
        $line =~ /\s*\*\s(.*?)\.(.*)/;
        #&Foswiki::Func::writeDebug( "TOPIC = $1.$2" );
        $result[++$#result] = "$1.$2";
    } elsif ( ( $test eq "Web" ) || ( $test eq "Regex" ) ) {
      $line =~ /\s*\*\s(.*)/;
      #&Foswiki::Func::writeDebug( "RESULT = $1" );
      $result[++$#result] = $1;
      }
    $test = $1 if ( $line =~ /$sections[$section]/ );
  }
  return @result;
}

sub notifyUsers {
  my ( $notifyUsers, $subject, $body ) = @_;
  #&Foswiki::Func::writeDebug( "NT = $notifyUsers" );
  foreach my $tmp ( @{$notifyUsers} ) {
    &Foswiki::Func::writeDebug( "MAIL SENT TO $tmp ..." );
    #my $email = "Date: ".&Foswiki::handleTime("","gmtime")."\n";
    my $email .= "From: $sender\n";
    $email .= "To: ".getUserEmail( $tmp )."\n";
    $email .= "CC: \n";
    $email .= "Subject: $subject\n\n";
    $email .= "$body\n";
    #&Foswiki::Func::writeDebug( "Sending mail to $tmp ..." );
    my $error = &Foswiki::Net::sendEmail( $email );
    if ( $error ) {
      &Foswiki::Func::writeDebug( "ERROR WHILE SENDING MAIL - $error" );
    }
  }  
}

sub getUserEmail {
  my $who = shift;
  my @emails = &Foswiki::getEmailOfUser( $who );
  return "" if ( $#emails < 0 );
  #&Foswiki::Func::writeDebug( "USER: $user, EMAIL $emails[0]" );
  return $emails[0];
}

sub addItemToNotifyList {
  my $who = shift;
  my $what = shift;
  my $section = shift;
  my $meta = shift || "";
  my $text = shift || "";
  #&Foswiki::Func::writeDebug( "NTF:addItemToNotifyList: adding '$what' to section $sections[$section]" );
  ( $meta, $text ) = checkUserNotifyList( $who ) if ( $text eq "" );
  return ( $meta, $text ) if ( isItemInSection( $who, $what, $section, $text ) );
  my @items = &Foswiki::Plugins::NotificationPlugin::getNotificationsOfUser( $Foswiki::wikiName, $section, $text );
  my $newText = "";
  my $tmp = 0;
  foreach $line ( split( /\n/, $text ) ) {
    #&Foswiki::Func::writeDebug( "LINE = $line" );
    $tmp = 0 if ( $line =~ /^---\+\+\s/ && $tmp );
    $tmp = 1 if ( $line =~ /$sections[$section]/ );
    if ( $tmp == 0 ) {
      $newText .= "$line\n";
    }
    if ( $tmp == 1 ) {
      $newText .= "$line\n";
      foreach my $item ( @items ) {
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
  my $who = shift;
  my $what = shift;
  my $section = shift;
  my $meta = shift || "";
  my $text = shift || "";
  #&Foswiki::Func::writeDebug( "NTF:removeItemFromNotifyList: removing '$what' from section $sections[$section]" );
  ( $meta, $text ) = checkUserNotifyList( $who ) if ( $text eq "" );
  return ( $meta, $text ) if ( !isItemInSection( $who, $what, $section, $text ) );
  my @items = &Foswiki::Plugins::NotificationPlugin::getNotificationsOfUser( $Foswiki::wikiName, $section, $text );
  my $newText = "";
  my $tmp = 0;
  foreach $line ( split( /\n/, $text ) ) {
    $tmp = 0 if ( $line =~ /^---\+\+\s/ && $tmp );
    $tmp = 1 if ( $line =~ /$sections[$section]/ );
    if ( $tmp == 0 ) {
      $newText .= "$line\n";
    }
    if ( $tmp == 1 ) {
      $newText .= "$line\n";
      foreach my $item ( @items ) {
        #&Foswiki::Func::writeDebug( "ITEM = ^$item^" );
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
  #&Foswiki::Func::writeDebug( "NTF:checkUserNotifyList: WHO = $who" );
  if ( !&Foswiki::Func::topicExists( "Main", $who."NotifyList" ) ) {
    &Foswiki::Func::writeDebug( "TEST1" );
    ( $tmpMeta, $tmpText ) = &Foswiki::Func::readTopic( "Main", "NotificationPluginListTemplate" );
    $tmpMeta->put( "TOPICPARENT", ( "name" => $who ) );
    saveUserNotifyList( $who, $tmpMeta, $tmpText );
  } else {
    ( $tmpMeta, $tmpText ) = &Foswiki::Func::readTopic( "Main", $who."NotifyList" );
  }
  return ( $tmpMeta, $tmpText );
}

sub saveUserNotifyList {
  my ( $who, $meta, $text ) = @_;
  #&Foswiki::Func::writeDebug( "NTF:saveUserNotifyList: Saving Main.".$who."NotifyList topic..." );
  $text =~ s/   /\t/g;
  my $repRev = "repRev";
  $repRev = "" if ( !&Foswiki::Func::topicExists( "Main", $who."NotifyList" ) );
  my $error = &Foswiki::Store::saveTopic( "Main", $who."NotifyList", $text, $meta, $repRev, "checked", "checked" );
  if ( $error ) {
    my $url = &Foswiki::Func::getOopsUrl( $web, $topic, "oopssaveerr", $error );
    &Foswiki::Func::redirectCgiQuery( $query, $url );
  }    
}

sub isItemInSection {
  my $who = shift;
  my $what = shift;
  my $section = shift;
  my $text = shift || "";
  #&Foswiki::Func::writeDebug( "NTF:isItemInSection: WHO = $who, WHT = $what, SCT = $section, TXT = ".length( $text ) );
  my $meta;
  ( $meta, $text ) = checkUserNotifyList( $who ) if ( $text eq "" );
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
  $tin = $1 if ( $attrs =~ /tin=\"(.*?)\"/ );
  $win = $1 if ( $attrs =~ /win=\"(.*?)\"/ ); 
  $tn = $1 if ( $attrs =~ /tn=\"(.*?)\"/ );
  $wn = $1 if ( $attrs =~ /wn=\"(.*?)\"/ );
  $popup = $1 if ( $attrs =~ /popup=\"(.*?)\"/ );
  $opt = $1 if ( $attrs =~ /optional=\"(.*?)\"/ );
  my $text = "";
  if ( $Foswiki::wikiName ne "WikiGuest" ) {
    $tinOn = "off" if ( !isItemInSection( $Foswiki::wikiName, "$web.$topic", 0 ) );
    $winOn = "off" if ( !isItemInSection( $Foswiki::wikiName, "$web", 1 ) );
    $tnOn = "off" if ( !isItemInSection( $Foswiki::wikiName, "$web.$topic", 3 ) );
    $wnOn = "off" if ( !isItemInSection( $Foswiki::wikiName, "$web", 4 ) );
    $text .= "<input onClick='javascript:window.open(\"".&Foswiki::Func::getScriptUrl( $web, $topic, "changenotify" )."?popup=on\");' type='button' value='Popup'>&nbsp;" if ( $popup eq "on" );
    $text .= "<input onClick='javascript:location.href(\"".&Foswiki::Func::getScriptUrl( $web, $topic, "changenotify" )."?what=TIN&action=$tmp{$tinOn}&$opt\");' type='button' value='TIN $tinOn' title='Topic immediate notifications! Click to set it $tmp{$tinOn}!'>&nbsp;" if ( $tin eq "on" );
    $text .= "<input onClick='javascript:location.href(\"".&Foswiki::Func::getScriptUrl( $web, $topic, "changenotify" )."?what=WIN&action=$tmp{$winOn}&$opt\");' type='button' value='WIN $winOn' title='Web immediate notifications! Click to set it $tmp{$winOn}!'>&nbsp;" if ( $win eq "on" );
    $text .= "<input onClick='javascript:location.href(\"".&Foswiki::Func::getScriptUrl( $web, $topic, "changenotify" )."?what=TN&action=$tmp{$tnOn}&$opt\");' type='button' value='TN $tnOn' title='Topic notifications! Click to set it $tmp{$tnOn}!'>&nbsp;" if ( $tn eq "on" );
    $text .= "<input onClick='javascript:location.href(\"".&Foswiki::Func::getScriptUrl( $web, $topic, "changenotify" )."?what=WN&action=$tmp{$wnOn}&$opt\");' type='button' value='WN $wnOn' title='Web notifications! Click to set it $tmp{$wnOn}!'>&nbsp;" if ( $wn eq "on" );
  }
  return $text;
}

1;
