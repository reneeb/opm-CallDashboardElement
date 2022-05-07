# --
# Kernel/Language/hu_CallDashboardElement.pm - the Hungarian translation of CallDashboardElement
# Copyright (C) 2016 - 2022 Perl-Services.de, https://www.perl-services.de/
# Copyright (C) 2016 Balázs Úr, http://www.otrs-megoldasok.hu/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Language::hu_CallDashboardElement;

use strict;
use warnings;
use utf8;

sub Data {
    my $Self = shift;

    my $Lang = $Self->{Translation} || {};

    # Custom/Kernel/Modules/AgentCallDashboardElement.pm
    $Lang->{'No such config for %s!'} = 'Nincs ilyen beállítás ehhez: %s!';
    $Lang->{'Please contact the administrator.'} = 'Vegye fel a kapcsolatot a rendszergazdával.';
    $Lang->{'Can\'t get element data of %s!'} = 'Nem lehet lekérni a(z) %s elemadatait!';

    # Kernel/Config/Files/CallDashboardElement.xml
    $Lang->{'Frontend module registration for the agent interface.'} =
        'Előtétprogram-modul regisztráció az ügyintézői felülethez.';
    $Lang->{'Agent dashboard.'} = 'Ügyintézői vezérlőpult.';
    $Lang->{'Agent Dashboard'} = 'Ügyintézői vezérlőpult';
}

1;
