# --
# Kernel/Modules/AgentCallDashboardElement.pm
# Copyright (C) 2015 - 2016 Perl-Services.de, http://perl-services.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentCallDashboardElement;

use strict;
use warnings;

use Kernel::Language qw(Translatable);
use Kernel::System::VariableCheck qw(:all);
use Kernel::System::ObjectManager;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $BackendConfigKey  = 'DashboardBackend';
    my $MainMenuConfigKey = 'AgentDashboard::MainMenu';
    my $UserSettingsKey   = 'UserDashboard';

    # load backends
    my $ConfigObject       = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject       = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject        = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');

    my $Config = $ConfigObject->Get($BackendConfigKey);
    if ( !$Config ) {
        return $LayoutObject->ErrorScreen(
            Message => $LayoutObject->{LanguageObject}->Translate( 'No such config for %s.', $BackendConfigKey ),
            Comment => Translatable('Please contact the administrator.'),
        );
    }

    my $Name = $ParamObject->GetParam( Param => 'Name' );

    # get the column filters from the web request
    my %ColumnFilter;
    my %GetColumnFilter;
    my %GetColumnFilterSelect;

    COLUMNNAME:
    for my $ColumnName (
        qw(Owner Responsible State Queue Priority Type Lock Service SLA CustomerID CustomerUserID)
        )
    {
        my $FilterValue = $ParamObject->GetParam( Param => 'ColumnFilter' . $ColumnName . $Name )
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
    $Self->{DynamicField} = $DynamicFieldObject->DynamicFieldListGet(
        Valid      => 1,
        ObjectType => ['Ticket'],
    );

    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);
        next DYNAMICFIELD if !$DynamicFieldConfig->{Name};

        my $FilterValue = $ParamObject->GetParam(
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

    my $SortBy  = $ParamObject->GetParam( Param => 'SortBy' );
    my $OrderBy = $ParamObject->GetParam( Param => 'OrderBy' );

    my $DBObject     = $Kernel::OM->Get('Kernel::System::DB');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # use a slave db to search dashboard date
    if ( $ConfigObject->Get('Core::MirrorDB::DSN') ) {

        local $Kernel::OM = Kernel::System::ObjectManager->new(
            'Kernel::System::DB' => {
                DatabaseDSN  => $ConfigObject->Get('Core::MirrorDB::DSN'),
                DatabaseUser => $ConfigObject->Get('Core::MirrorDB::User'),
                DatabasePw   => $ConfigObject->Get('Core::MirrorDB::Password'),
            },
        );

        $DBObject     = $Kernel::OM->Get('Kernel::System::DB');
        $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    }


    my %Element = $Self->_Element(
        Name                  => $Name,
        Configs               => $Config,
        TicketObject          => $TicketObject,
        DBObject              => $DBObject,
        AJAX                  => 1,
        SortBy                => $SortBy,
        OrderBy               => $OrderBy,
        ColumnFilter          => \%ColumnFilter,
        GetColumnFilter       => \%GetColumnFilter,
        GetColumnFilterSelect => \%GetColumnFilterSelect,
    );

    if ( !%Element ) {
        $LayoutObject->FatalError(
            Message => $LayoutObject->{LanguageObject}->Translate( 'Can\'t get element data of %s!', $Name ),
            Comment => Translatable('Please contact the administrator.'),
        );
    }

    return $LayoutObject->Attachment(
        ContentType => 'text/html',
        Charset     => $LayoutObject->{UserCharset},
        %{ $Element{Header} || {} },
        Content     => ${ $Element{Content} },
        NoCache     => 1,
    );
}

sub _Element {
    my ( $Self, %Param ) = @_;

    my $MainObject = $Kernel::OM->Get('Kernel::System::Main');

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
    return if !$MainObject->Require($Module);

    my $Object = $Module->new(
        %{$Self},
        DBObject              => $Param{DBObject},
        TicketObject          => $Param{TicketObject},
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
