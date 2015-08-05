# --
# Kernel/Modules/AgentCallDashboardElement.pm
# Copyright (C) 2015 Perl-Services.de, http://perl-services.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentCallDashboardElement;

use strict;
use warnings;

use Kernel::System::CustomerCompany;
use Kernel::System::DynamicField;
use Kernel::System::DynamicField::Backend;
use Kernel::System::VariableCheck qw(:all);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # check needed objects
    for (qw(ParamObject DBObject LayoutObject LogObject ConfigObject MainObject EncodeObject)) {
        if ( !$Self->{$_} ) {
            $Self->{LayoutObject}->FatalError( Message => "Got no $_!" );
        }
    }

    $Self->{CacheObject}           = $Kernel::OM->Get('Kernel::System::Cache');
    $Self->{CustomerCompanyObject} = Kernel::System::CustomerCompany->new(%Param);

    $Self->{SlaveDBObject}     = $Self->{DBObject};
    $Self->{SlaveTicketObject} = $Self->{TicketObject};

    # use a slave db to search dashboard date
    if ( $Self->{ConfigObject}->Get('Core::MirrorDB::DSN') ) {

        $Self->{SlaveDBObject} = Kernel::System::DB->new(
            LogObject    => $Param{LogObject},
            ConfigObject => $Param{ConfigObject},
            MainObject   => $Param{MainObject},
            EncodeObject => $Param{EncodeObject},
            DatabaseDSN  => $Self->{ConfigObject}->Get('Core::MirrorDB::DSN'),
            DatabaseUser => $Self->{ConfigObject}->Get('Core::MirrorDB::User'),
            DatabasePw   => $Self->{ConfigObject}->Get('Core::MirrorDB::Password'),
        );

        if ( $Self->{SlaveDBObject} ) {

            $Self->{SlaveTicketObject} = Kernel::System::Ticket->new(
                %Param,
                DBObject => $Self->{SlaveDBObject},
            );
        }
    }

    # create extra needed objects
    $Self->{DynamicFieldObject} = Kernel::System::DynamicField->new(%Param);
    $Self->{BackendObject}      = Kernel::System::DynamicField::Backend->new(%Param);
    $Self->{StatsObject}        = Kernel::System::Stats->new(%Param);

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $BackendConfigKey  = 'DashboardBackend';
    my $MainMenuConfigKey = 'AgentDashboard::MainMenu';
    my $UserSettingsKey   = 'UserDashboard';

    # load backends
    my $Config = $Self->{ConfigObject}->Get($BackendConfigKey);
    if ( !$Config ) {
        return $Self->{LayoutObject}->ErrorScreen(
            Message => 'No such config for ' . $BackendConfigKey,
        );
    }

    my $Name = $Self->{ParamObject}->GetParam( Param => 'Name' );

    # get the column filters from the web request
    my %ColumnFilter;
    my %GetColumnFilter;
    my %GetColumnFilterSelect;

    COLUMNNAME:
    for my $ColumnName (
        qw(Owner Responsible State Queue Priority Type Lock Service SLA CustomerID CustomerUserID)
        )
    {
        my $FilterValue = $Self->{ParamObject}->GetParam( Param => 'ColumnFilter' . $ColumnName . $Name )
            || '';
        next COLUMNNAME if $FilterValue eq '';

        if ( $ColumnName eq 'CustomerID' ) {
            push @{ $ColumnFilter{$ColumnName} }, $FilterValue;
        }
        elsif ( $ColumnName eq 'CustomerUserID' ) {
            push @{ $ColumnFilter{CustomerUserLogin} }, $FilterValue;
        }
        else {
            push @{ $ColumnFilter{ $ColumnName . 'IDs' } }, $FilterValue;
        }

        $GetColumnFilter{ $ColumnName . $Name } = $FilterValue;
        $GetColumnFilterSelect{$ColumnName} = $FilterValue;
    }

    # get all dynamic fields
    $Self->{DynamicField} = $Self->{DynamicFieldObject}->DynamicFieldListGet(
        Valid      => 1,
        ObjectType => ['Ticket'],
    );

    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);
        next DYNAMICFIELD if !$DynamicFieldConfig->{Name};

        my $FilterValue = $Self->{ParamObject}->GetParam(
            Param => 'ColumnFilterDynamicField_' . $DynamicFieldConfig->{Name} . $Name
        );

        next DYNAMICFIELD if !defined $FilterValue;
        next DYNAMICFIELD if $FilterValue eq '';

        $ColumnFilter{ 'DynamicField_' . $DynamicFieldConfig->{Name} } = {
            Equals => $FilterValue,
        };
        $GetColumnFilter{ 'DynamicField_' . $DynamicFieldConfig->{Name} . $Name } = $FilterValue;
        $GetColumnFilterSelect{ 'DynamicField_' . $DynamicFieldConfig->{Name} } = $FilterValue;
    }

    my $SortBy  = $Self->{ParamObject}->GetParam( Param => 'SortBy' );
    my $OrderBy = $Self->{ParamObject}->GetParam( Param => 'OrderBy' );

    my %Element = $Self->_Element(
        Name                  => $Name,
        Configs               => $Config,
        AJAX                  => 1,
        SortBy                => $SortBy,
        OrderBy               => $OrderBy,
        ColumnFilter          => \%ColumnFilter,
        GetColumnFilter       => \%GetColumnFilter,
        GetColumnFilterSelect => \%GetColumnFilterSelect,
    );

    if ( !%Element ) {
        $Self->{LayoutObject}->FatalError(
            Message => "Can't get element data of $Name!",
        );
    }

    return $Self->{LayoutObject}->Attachment(
        ContentType => 'text/html',
        Charset     => $Self->{LayoutObject}->{UserCharset},
        %{ $Element{Header} || {} },
        Content     => ${ $Element{Content} },
        NoCache     => 1,
    );
}

sub _Element {
    my ( $Self, %Param ) = @_;

    my $Name                  = $Param{Name};
    my $Configs               = $Param{Configs};
    my $Backends              = $Param{Backends};
    my $SortBy                = $Param{SortBy};
    my $OrderBy               = $Param{OrderBy};
    my $ColumnFilter          = $Param{ColumnFilter};
    my $GetColumnFilter       = $Param{GetColumnFilter};
    my $GetColumnFilterSelect = $Param{GetColumnFilterSelect};

    # check permissions
    if ( $Configs->{$Name}->{Group} ) {
        my $PermissionOK = 0;
        my @Groups = split /;/, $Configs->{$Name}->{Group};
        GROUP:
        for my $Group (@Groups) {
            my $Permission = 'UserIsGroupRo[' . $Group . ']';
            if ( defined $Self->{$Permission} && $Self->{$Permission} eq 'Yes' ) {
                $PermissionOK = 1;
                last GROUP;
            }
        }
        return if !$PermissionOK;
    }

    # load backends
    my $Module = $Configs->{$Name}->{Module};
    return if !$Self->{MainObject}->Require($Module);
    my $Object = $Module->new(
        %{$Self},
        DBObject              => $Self->{SlaveDBObject},
        TicketObject          => $Self->{SlaveTicketObject},
        Config                => $Configs->{$Name},
        Name                  => $Name,
        CustomerID            => $Self->{CustomerID} || '',
        SortBy                => $SortBy,
        OrderBy               => $OrderBy,
        ColumnFilter          => $ColumnFilter,
        GetColumnFilter       => $GetColumnFilter,
        GetColumnFilterSelect => $GetColumnFilterSelect,

    );

    # get module config
    my %Config = $Object->Config();

    # get module preferences
    my @Preferences = $Object->Preferences();
    return @Preferences if $Param{PreferencesOnly};

    if ( $Param{FilterContentOnly} ) {
        my $FilterContent = $Object->FilterContent(
            FilterColumn => $Param{FilterColumn},
            Config       => $Configs->{$Name},
            Name         => $Name,
            CustomerID   => $Self->{CustomerID} || '',
        );
        return $FilterContent;
    }

    # check backends cache (html page cache)
    my ($Header, $Content) = $Object->Run(
        AJAX       => $Param{AJAX},
        CustomerID => $Self->{CustomerID} || '',
    );

    $Content //= $Header;

    # check if content should be shown
    return if !$Content;

    $Header = {} if !ref $Header;

    # return result
    return (
        Content     => \$Content,
        Config      => \%Config,
        Preferences => \@Preferences,
        Header      => $Header,
    );
}

1;
