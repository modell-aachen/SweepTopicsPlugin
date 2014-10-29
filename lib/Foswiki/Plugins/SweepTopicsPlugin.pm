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
    my $transitionedSth = 0;
    my $updatedActions = 0;
    my $errors = 0;

    my ($meta, $text) = Foswiki::Func::readTopic($cweb, $ctopic);

    return 'Controller table not found!' unless $text =~ m#^\|\s+\*?Action\*?\s+\|\s+\*?Type\*?\s+\|\s+\*?Web\*?\s+\|\s+\*?Query\*?\s+\|\s*?\n#g;

    while ($text =~ m#\G\|\s*([^|]+)\s*\|\s*([^|\s]*)\s*\|\s*([^|\s]*)\s*\|\s*([^|]+?)\s*\|\s*?\n#g) {
        my $action = $1;
        my $type = $2;
        my $sweepWeb = $3 || $cweb;
        my $query = $4;
        $list.= "</p>\n<p>---$action in $sweepWeb with $type: '$query'---<br />\n";

        my @topicArray;
        if ($type =~ m/^\s*QuerySearch\s*$/) {
            @topicArray = _doStandardSearch($query, $sweepWeb, $ctopic);
        } elsif ($type =~ m/^\s*SolrSearch\s*$/) {
            @topicArray = _doSolrSearch($query, $sweepWeb, $ctopic);
        } elsif ($type =~ m/^\s*SolrActionSearch\s*$/) {
            @topicArray = _doSolrActionSearch($query, $sweepWeb, $ctopic);
        } else {
            $list .= "!Unknown search type!\n";
            next;
        }

        if ($action eq 'Delete') {
            foreach my $eachWebTopic (@topicArray) {
                my ($eachWeb, $eachTopic) = Foswiki::Func::normalizeWebTopicName(undef, $eachWebTopic);
                $list .= "$eachWeb.$eachTopic <br />\n";
                unless ($listonly) {
                    try {
                        $deletedSth++;
                        _trashTopic( $eachWeb, $eachTopic );
                    } catch Error::Simple with {
                        my $e = shift;
                        Foswiki::Func::writeWarning( $e );
                        $list .= '! Error !';
                        $errors++;
                    }
                }
            }
        } elsif ($action =~ m#Transition\((.*)\)#) {
            my $transitionsString = $1;
            my @transitions = ();
            while($transitionsString =~ m#{(.*?)}#g) {
                my $params = $1;
                my $transitionParams = {};
                unless ($params =~ m#state="(.*?)"#) {
                    Foswiki::Func::writeWarning("Missing state in $action");
                    $list .= '! Error !';
                    $errors++;
                    next;
                }
                $transitionParams->{state} = $1;
                unless ($params =~ m#action="(.*?)"#) {
                    Foswiki::Func::writeWarning("Missing action in $action");
                    $list .= '! Error !';
                    $errors++;
                    next;
                }
                $transitionParams->{action} = $1;
                my $remark;
                if ($params =~ m#remark="(.*?)"#) {
                    $remark = $1;
                }
                my $deleteComments;
                if ($params =~ m#deleteComments="(.*?)"#) {
                    $transitionParams->{action} = $1;
                }
                $transitionParams->{breaklock} = 1;
                if ($params =~ m#breaklock="(.*?)"#) {
                    $transitionParams->{breaklock} = $1;
                }
                push(@transitions, $transitionParams);
            }
            foreach my $eachWebTopic (@topicArray) {
                my ($eachWeb, $eachTopic) = Foswiki::Func::normalizeWebTopicName(undef, $eachWebTopic);
                $list .= "$eachWeb.$eachTopic <br />\n";
                unless ($listonly) {
                    try {
                        $transitionedSth++;
                        foreach my $transition (@transitions) {
                            my $report = Foswiki::Plugins::KVPPlugin::transitionTopic($session, $eachWeb, $eachTopic, $transition->{action}, $transition->{state}, $transition->{remark}, $transition->{deleteComments}, $transition->{breaklock});
                            next unless $report;
                            $eachWeb = $report->{webAfterTransition} || $eachWeb;
                            $eachTopic = $report->{topicAfterTransition} || $eachTopic;
                        }
                    } catch Foswiki::OopsException with {
                        my $e = shift;
                        my $params = $e->{params};
                        Foswiki::Func::writeWarning( "def: $e->{def} params: ".join(',', @$params ));
                        $list .= '! Error !';
                        $errors++;
                    }
                }
            }
        } elsif ($action =~ m#ActionTracker\((.*)\)#) {
            my $actionString = $1;
            my %changes;
            if($actionString =~ m#state\s*=\s*"(.*?)"#) {
                $changes{'state'} = $1;
            }
            if(scalar keys %changes) {
                use Foswiki::Plugins::ActionTrackerPlugin;
                foreach my $eachWebTopicUid (@topicArray) {
                    next unless $eachWebTopicUid =~ m/^(.+)#(.+)$/;
                    my $eachWebTopic = $1;
                    my $eachUid = $2;
                    my ($eachWeb, $eachTopic) = Foswiki::Func::normalizeWebTopicName(undef, $eachWebTopic);
                    $list .= "$eachWeb.$eachTopic#$eachUid <br />\n";
                    unless ($listonly) {
                        try {
                            Foswiki::Plugins::ActionTrackerPlugin::lazyInit( $eachWeb, $eachTopic );
                            Foswiki::Plugins::ActionTrackerPlugin::_updateSingleAction($eachWeb, $eachTopic, $eachUid, %changes); # XXX private method
                            $updatedActions++;
                        }
                        catch Error::Simple with {
                            my $e = shift;
                            Foswiki::Func::writeWarning($e);
                            $list .='! Error !';
                            $errors++;
                        }
                        catch Foswiki::AccessControlException with {
                            my $e = shift;
                            Foswiki::Func::writeWarning($e);
                            $list .='! Error !';
                            $errors++;
                        };
                    }
                }
            }
        } else {
            # nothing but delete yet
            $list .= "!Unknown action: '$action'!\n";
            $errors++;
            next;
        }
    }
    $list .= "</p>\n<p>Deleted: $deletedSth </p>\n"; # These will be meaningless on Test-runs, yet reassuring
    $list .= "</p>\n<p>Transitioned: $transitionedSth </p>\n";
    $list .= "</p>\n<p>Actions: $updatedActions </p>\n";
    $list .= "</p>\n<p>Errors: $errors </p>\n";
    $list = "<html><head></head><body>$list</body></html>";
    if ($listonly) {
        return $list;
    }
    if ($deletedSth || $transitionedSth || $updatedActions || ($errors && !$listonly)) {
        my $w = Foswiki::Func::getWorkArea( "SweepTopicsPlugin" );
        open FILE, ">", $w.'/'.time().'.log';
        print FILE $list;
        close FILE;
    }
    return undef;
}

sub _doSolrActionSearch {
    my ( $query, $web, $topic ) = @_;

    my $webparam = ($web)?" web:$web":'';
    my $response = Foswiki::Func::expandCommonVariables( <<SEARCH, $topic, $web );
%SOLRSEARCH{"type:action $query$webparam" fields="webtopic,action_uid_s" format="\$webtopic#\$action_uid_s" separator="|" rows="999"}%
SEARCH

    $response =~ s#^\s*##;
    $response =~ s#\s*$##;
    return split('\|', $response);
}

sub _doSolrSearch {
    my ( $query, $web, $topic ) = @_;

    my $webparam = ($web)?" web:$web":'';
    my $response = Foswiki::Func::expandCommonVariables( <<SEARCH, $topic, $web );
%SOLRSEARCH{"type:topic $query$webparam" fields="webtopic" format="\$webtopic" separator="|" rows="999"}%
SEARCH

    $response =~ s#^\s*##;
    $response =~ s#\s*$##;
    return split('\|', $response);
}

sub _doStandardSearch {
    my ( $query, $web, $topic ) = @_;

    my $response = Foswiki::Func::expandCommonVariables( <<SEARCH, $topic, $web );
%SEARCH{"$query" format="\$web.\$topic" separator="|" type="query" nonoise="on" web="$web"}%
SEARCH

    return split('\|', $response);
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
