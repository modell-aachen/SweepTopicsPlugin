# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
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

package Foswiki::Plugins::SweepTopicsPlugin;

# Always use strict to enforce variable scoping
use strict;
use warnings;

use Foswiki::Func    ();    # The plugins API
use Foswiki::Plugins ();    # For the API version
use Error ':try';

# $VERSION is referred to by Foswiki, and is the only global variable that
# *must* exist in this package. This should always be in the format
# $Rev$ so that Foswiki can determine the checked-in status of the
# extension.
our $VERSION = '$Rev$';

# $RELEASE is used in the "Find More Extensions" automation in configure.
# It is a manually maintained string used to identify functionality steps.
# You can use any of the following formats:
# tuple   - a sequence of integers separated by . e.g. 1.2.3. The numbers
#           usually refer to major.minor.patch release or similar. You can
#           use as many numbers as you like e.g. '1' or '1.2.3.4.5'.
# isodate - a date in ISO8601 format e.g. 2009-08-07
# date    - a date in 1 Jun 2009 format. Three letter English month names only.
# Note: it's important that this string is exactly the same in the extension
# topic - if you use %$RELEASE% with BuildContrib this is done automatically.
our $RELEASE = "1.0";

# Short description of this plugin
# One line description, is shown in the %SYSTEMWEB%.TextFormattingRules topic:
our $SHORTDESCRIPTION = 'Deletes obviously unused topics.';

# You must set $NO_PREFS_IN_TOPIC to 0 if you want your plugin to use
# preferences set in the plugin topic. This is required for compatibility
# with older plugins, but imposes a significant performance penalty, and
# is not recommended. Instead, leave $NO_PREFS_IN_TOPIC at 1 and use
# =$Foswiki::cfg= entries, or if you want the users
# to be able to change settings, then use standard Foswiki preferences that
# can be defined in your %USERSWEB%.SitePreferences and overridden at the web
# and topic level.
#
# %SYSTEMWEB%.DevelopingPlugins has details of how to define =$Foswiki::cfg=
# entries so they can be used with =configure=.
our $NO_PREFS_IN_TOPIC = 1;

=begin TML

---++ initPlugin($topic, $web, $user) -> $boolean
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$user= - the login name of the user
   * =$installWeb= - the name of the web the plugin topic is in
     (usually the same as =$Foswiki::cfg{SystemWebName}=)

*REQUIRED*

Called to initialise the plugin. If everything is OK, should return
a non-zero value. On non-fatal failure, should write a message
using =Foswiki::Func::writeWarning= and return 0. In this case
%<nop>FAILEDPLUGINS% will indicate which plugins failed.

In the case of a catastrophic failure that will prevent the whole
installation from working safely, this handler may use 'die', which
will be trapped and reported in the browser.

__Note:__ Please align macro names with the Plugin name, e.g. if
your Plugin is called !FooBarPlugin, name macros FOOBAR and/or
FOOBARSOMETHING. This avoids namespace issues.

=cut

sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 2.0 ) {
        Foswiki::Func::writeWarning( 'Version mismatch between ',
            __PACKAGE__, ' and Plugins.pm' );
        return 0;
    }

    # Example code of how to get a preference value, register a macro
    # handler and register a RESTHandler (remove code you do not need)

    # Set your per-installation plugin configuration in LocalSite.cfg,
    # like this:
    # $Foswiki::cfg{Plugins}{SweepTopicsPlugin}{ExampleSetting} = 1;
    # See %SYSTEMWEB%.DevelopingPlugins#ConfigSpec for information
    # on integrating your plugin configuration with =configure=.

    # Always provide a default in case the setting is not defined in
    # LocalSite.cfg.
    # my $setting = $Foswiki::cfg{Plugins}{SweepTopicsPlugin}{ExampleSetting} || 0;

    # Allow a sub to be called from the REST interface
    # using the provided alias
    Foswiki::Func::registerRESTHandler( 'sweep', \&restSweep );

    # Plugin correctly initialized
    return 1;
}

=pod

---++ restExample($session) -> $text

This is an example of a sub to be called by the =rest= script. The parameter is:
   * =$session= - The Foswiki object associated to this session.

Additional parameters can be recovered via the query object in the $session, for example:

my $query = $session->{request};
my $web = $query->{param}->{web}[0];

If your rest handler adds or replaces equivalent functionality to a standard script
provided with Foswiki, it should set the appropriate context in its switchboard entry.
A list of contexts are defined in %SYSTEMWEB%.IfStatements#Context_identifiers.

For more information, check %SYSTEMWEB%.CommandAndCGIScripts#rest

For information about handling error returns from REST handlers, see
Foswiki:Support.Faq1

*Since:* Foswiki::Plugins::VERSION 2.0

=cut

sub restSweep {
    my ( $session, $subject, $verb, $response ) = @_;

    return 'Only admins may do this!' unless Foswiki::Func::isAnAdmin();

    my $query = $session->{request};
    my $cweb = $query->{param}->{cweb}[0];
    my $ctopic = $query->{param}->{ctopic}[0];
    my $listonly = $query->{param}->{listonly};

    return 'Please specify web and controlling topic' unless (defined $cweb && defined $ctopic);
    return "controlling topic '$cweb.$ctopic' does not exist!" unless (Foswiki::Func::topicExists($cweb, $ctopic));

    my $list = '<p>Result:';
    my $deletedSth = 0;

    my ($meta, $text) = Foswiki::Func::readTopic($cweb, $ctopic);

    return 'Controller table not found!' unless $text =~ m#^\|\s+\*?Action\*?\s+\|\s+\*?Type\*?\s+\|\s+\*?Web\*?\s+\|\s+\*?Query\*?\s+\|\s*?\n#g;

    while ($text =~ m#\G\|\s*([^|\s]+)\s*\|\s*([^|\s]*)\s*\|\s*([^|\s]*)\s*\|\s*([^|]+?)\s*\|\s*?\n#g) {
        my $action = $1;
        my $type = $2;
        my $sweepWeb = $3 || $cweb;
        my $query = $4;
        $list.= "</p>\n<p>---$action in $sweepWeb with $type: '$query'---<br />\n";

        my $topics = '';
        if ($type =~ m/^\s*QuerySearch\s*$/) {
            $topics = _doStandardSearch($query, $sweepWeb, $ctopic);
        } elsif ($type =~ m/^\s*SolrSearch\s*$/ && 'not yet' eq 'implemented') {
            $topics = _doSolrSearch($query, $sweepWeb, $ctopic);
        } else {
            $list .= "!Unknown search type!\n";
            next;
        }
        if ($action ne 'Delete') {
            # nothing but delete yet
            $list .= "!Unknown action: '$action'!\n";
            next;
        }
        my @topicArray = split('\|', $topics);

        foreach my $eachTopic (@topicArray) {
            $list .= "$sweepWeb.$eachTopic <br />\n";
            unless ($listonly) {
                try {
                    $deletedSth++;
                    _trashTopic( $sweepWeb, $eachTopic );
                } catch Error::Simple with {
                    my $e = shift;
                    Foswiki::Func::writeWarning( $e );
                    $list .= '! Error !';
                }
            }
        }
    }
    $list .= "</p>\n<p>Deleted: $deletedSth </p>\n"; # This will be meaningless on Test-runs, yet reassuring
    $list = "<html><head></head><body>$list</body></html>";
    if ($listonly) {
        return $list;
    }
    if ($deletedSth) {
        my $w = Foswiki::Func::getWorkArea( "SweepTopicsPlugin" );
        open FILE, ">", $w.'/'.time().'.log';
        print FILE $list;
        close FILE;
    }
    return undef;
}

sub _doStandardSearch {
    my ( $query, $web, $topic ) = @_;

    my $response = Foswiki::Func::expandCommonVariables( <<SEARCH, $topic, $web );
%SEARCH{"$query" format="\$topic" separator="|" type="query" nonoise="on" web="$web"}%
SEARCH

    return $response;
}

# Will find a topic in trashweb to move $web.$topic to by adding a numbered suffix.
# Copy/Paste KVPPlugin
sub _trashTopic {
    my ($web, $topic) = @_;

    my $trashWeb = $Foswiki::cfg{TrashWebName};

    my $trashTopic = $web . $topic;
    $trashTopic =~ s#/|\.##g; # remove subweb-deliminators

    my $numberedTrashTopic = $trashTopic;
    my $i = 1;
    while (Foswiki::Func::topicExists($trashWeb, $numberedTrashTopic)) {
        $numberedTrashTopic = $trashTopic."_$i";
        $i++;
    }

    Foswiki::Func::moveTopic( $web, $topic, $trashWeb, $numberedTrashTopic );
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Author: %$AUTHOR%

Copyright (C) 2008-2012 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.