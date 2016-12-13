# --
# Kernel/Language/de_CallDashboardElement.pm - the German translation of CallDashboardElement
# Copyright (C) 2016 Perl-Services.de, http://perl-services.de/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Language::de_CallDashboardElement;

use strict;
use warnings;
use utf8;

sub Data {
    my $Self = shift;

    my $Lang = $Self->{Translation} || {};

    # Custom/Kernel/Modules/AgentCallDashboardElement.pm
    $Lang->{'No such config for %s!'} = '';
    $Lang->{'Please contact the administrator.'} = '';
    $Lang->{'Can\'t get element data of %s!'} = '';

    # Kernel/Config/Files/CallDashboardElement.xml
    $Lang->{'Frontend module registration for the agent interface.'} =
        'Frontend-Modulregistrierung im Agent-Interface.';
    $Lang->{'Agent dashboard.'} = '';
    $Lang->{'Agent Dashboard'} = '';
}

1;
