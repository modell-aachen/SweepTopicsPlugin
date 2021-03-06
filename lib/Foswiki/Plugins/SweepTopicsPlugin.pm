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

our $VERSION = '1.0';

our $RELEASE = "1.0";

our $SHORTDESCRIPTION = 'Deletes obviously unused topics.';

our $NO_PREFS_IN_TOPIC = 1;

sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 2.0 ) {
        Foswiki::Func::writeWarning( 'Version mismatch between ',
            __PACKAGE__, ' and Plugins.pm' );
        return 0;
    }

    Foswiki::Func::registerRESTHandler( 'sweep', \&restSweep );

    # Plugin correctly initialized
    return 1;
}

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
