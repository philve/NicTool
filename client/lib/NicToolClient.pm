package NicToolClient;
# ABSTRACT: CGI Interface to NicToolServer

use strict;
use vars qw/ $AUTOLOAD /;
use NicToolServerAPI();

$NicToolClient::VERSION = '2.12';
$NicToolClient::NTURL   = 'http://www.nictool.com/';
$NicToolClient::LICENSE = 'http://www.affero.org/oagpl.html';
$NicToolClient::SRCURL  = 'http://www.nictool.com/download/NicTool.tar.gz';

sub new {
    my $class = shift;
    my $q     = shift;

    my $nt_server_obj = new NicToolServerAPI();

    bless { 'nt_server_obj' => $nt_server_obj, 'CGI' => $q }, $class;
}


sub help_link {
    my ($self,$helptopic, $text) = @_;

    return '' if !$NicToolClient::show_help_links;
    return qq{ &nbsp; [<a href="javascript:void window.open('help.cgi?topic=$helptopic', 'help_win', 'width=640,height=480,scrollbars,resizable=yes')">}
        . ( $text ? $text : '' )
        . qq{<img src="$NicToolClient::image_dir/help-small.gif" alt="Help"></a>]};
}

sub rr_types {
    my $self = shift;
    my $r = $self->get_record_type(type=>'ALL');
    return $r->{types};
}

sub obj_to_cgi_map {
    {   'nameserver' =>
            { 'image' => 'zone.gif', 'url' => 'group_nameservers.cgi' },
        'zone'        => { 'image' => 'zone.gif',     'url' => 'zone.cgi' },
        'user'        => { 'image' => 'user.gif',     'url' => 'user.cgi' },
        'group'       => { 'image' => 'group.gif',    'url' => 'group.cgi' },
        'zone_record' => { 'image' => 'r_record.gif', 'url' => 'zone.cgi' },
    };
}

sub check_setup {
    my $self = shift;

    my $server_obj = $self->{'nt_server_obj'};
    my $q          = $self->{'CGI'};

    my $message = $server_obj->check_setup();

    if ( $message ne 'OK' ) {
        print $q->header;
        $self->parse_template( $NicToolClient::setup_error_template,
            message => $message );
    }

    return $message;
}

sub login_user {
    my $self = shift;

    my $server_obj = $self->{'nt_server_obj'};
    my $q          = $self->{'CGI'};

    return $server_obj->send_request(
        action   => "login",
        username => $q->param('username'),
        password => $q->param('password')
    );
}

sub logout_user {
    my $self = shift;

    my $server_obj = $self->{'nt_server_obj'};
    my $q          = $self->{'CGI'};

    return $server_obj->send_request(
        action          => "logout",
        nt_user_session => $q->cookie('NicTool')
    );
}

sub display_login {
    my ( $self, $error ) = @_;

    my $q = $self->{'CGI'};

    my $cookie = $q->cookie(
        -name    => 'NicTool',
        -value   => '',
        -expires => '-1d',
        -path    => '/'
    );
    print $q->header( -cookie => $cookie );
    if ( !ref $error ) {
        $error = { 'error_code' => 'XXX', 'error_msg' => $error };
    }
    if ( $error->{'error_code'} ne 200 ) {
        $self->parse_template(
            $NicToolClient::login_template,
            'message' => $error->{'error_msg'}
        );
    }
    else {
        $self->parse_template($NicToolClient::login_template);
    }

}

sub verify_session {
    my $self = shift;

    my $server_obj = $self->{'nt_server_obj'};
    my $q          = $self->{'CGI'};

    my $response = $server_obj->send_request(
        action          => "verify_session",
        nt_user_session => $q->cookie('NicTool')
    );
    my $error_msg;

    #warn "verify_session response: ".Data::Dumper::Dumper($response);
    if ( ref($response) ) {
        if ( $response->{'error_code'} ) {
            $error_msg = $response->{'error_msg'};
        }
        else {
            return $response;
        }
    }
    else {
        $error_msg = $response;
    }

    my $cookie = $q->cookie(
        -name    => 'NicTool',
        -value   => '',
        -expires => '-1d',
        -path    => '/'
    );
    print $q->header( -cookie => $cookie ),
    qq[<html>
 <script>
  parent.location = 'index.cgi?message=] . $q->escape($error_msg) . qq[';
 </script>
</html>];

    $self->parse_template( $NicToolClient::login_template, 'message' => $error_msg );
}

sub parse_template {
    my $self     = shift;
    my $template = shift;

    my %temp = @_;
    my $vars = \%temp;

    # only for stuff defined in the $NicToolClient:: namespace
    $self->fill_template_vars($vars)
        ;    # TODO - cache # unless ($self->{'fill_vars'});

    open( FILE, "<$template" ) || die "unable to find template: $template\n";

    while (<FILE>) {
        s/{{(.+?)}}/$vars->{$1}/g;
        s/{{ONLOAD_JS}}/$temp{'ONLOAD_JS'}/g;
        print;
    }

    close(FILE);
}

sub fill_template_vars {
    my $self = shift;
    my $vars = shift;

    my @fields = qw( app_title app_dir image_dir generic_error_message VERSION SRCURL LICENSE NTURL );

    foreach my $f (@fields) {
        my $temp;
        eval "\$temp = \$NicToolClient::$f";
        $vars->{$f} = $temp;
    }
}

sub display_group_tree {
    my ( $self, $user, $user_group, $curr_group, $in_summary ) = @_;

    $curr_group ||= $user_group;

    my $rv = $self->{'nt_server_obj'}->send_request(
        action          => "get_group_branch",
        nt_group_id     => $curr_group,
        nt_user_session => $self->{'CGI'}->cookie('NicTool')
    );

    if ( $rv->{'error_code'} != 200 ) {
        $curr_group = $user_group;
        $rv         = $self->{'nt_server_obj'}->send_request(
            action          => "get_group_branch",
            nt_group_id     => $curr_group,
            nt_user_session => $self->{'CGI'}->cookie('NicTool')
        );
    }

    my $count = scalar( @{ $rv->{'groups'} } ) - 1;
    my @list;

    foreach my $navG ( 0 .. $count ) {
        my $group = $rv->{'groups'}->[$navG];
        push( @list, $group->{'name'} );

        my @options;
        if ( $group->{'nt_group_id'} != $user_group ) {
            my $name = 'View Details';
            if ($user->{'group_write'}
                && ( !exists $group->{'delegate_write'}
                    || $group->{'delegate_write'} )
                )
            {
                $name = 'Edit';
            };
            push @options, qq[<a href="group.cgi?nt_group_id=$group->{'nt_group_id'}&amp;edit=1">$name</a>];
            if ($user->{"group_delete"}
                && ( !exists $group->{'delegate_delete'}
                    || $group->{'delegate_delete'} )
                )
            {
                push @options, qq[<a href="group.cgi?nt_group_id=$group->{'parent_group_id'}&amp;delete=$group->{'nt_group_id'}" onClick="return confirm('Delete ]
                        . join( ' / ', @list )
                        . qq[ and all associated data?');">Delete</a>];
            }
            else {
                push @options, qq[<span class="disabled">Delete</span>];
            }
        }
        my $dir = qq[<img src="$NicToolClient::image_dir];
        my $folder = $dir . qq[/folder_closed.gif" alt="folder">];
        my $state = "cgi?nt_group_id=$group->{'nt_group_id'}";
        push @options, qq[$dir/zone.gif" alt="zone"><a href="group_zones.$state">Zones</a>];
        push @options, qq[$dir/nameserver.gif" alt="ns"><a href="group_nameservers.$state">Nameservers</a>];
        push @options, qq[$dir/user.gif" alt="user"><a href="group_users.$state">Users</a>];
        push @options, qq[$dir/group.gif" alt="group"><a href="group.$state">Groups</a>];
        push @options, qq[$folder <a href="group_log.$state">Log</a>];

        print qq[
<div id="navBar$navG" class="light_grey_bg side_pad">
 <span class="nowrap">];

        for my $x ( 1 .. $navG ) {
            my $img = $x == $navG ? 'dirtree_elbow' : 'transparent';
            print qq[\n  <img src="$NicToolClient::image_dir/$img.gif" class="tee" alt="$img">
];
        }

        print qq[<img src="$NicToolClient::image_dir/group.gif" alt="group">];

        if ( $in_summary && $navG == $count ) {
            print qq[<strong>$group->{'name'}</strong>];
        }
        else {
            print qq[<a href="group.cgi?nt_group_id=$group->{'nt_group_id'}">$group->{'name'}</a>];
        }

        print qq[</span>
 <span class="float_r no_wrap">], join( "\n&nbsp;|&nbsp;", @options), qq[ </span>
</div>];
    }

    return $count + 1;
}

sub display_zone_list_options {
    my ( $self, $user, $group_id, $level, $in_zone_list ) = @_;

    my $q = $self->{'CGI'};

    my @options;
    if ( $user->{'zone_create'} ) {
        if ( ! $in_zone_list ) {
            push @options, qq[<a href="group_zones.cgi?nt_group_id=$group_id&amp;new=1">New Zone</a>];
        };
    }
    else {
        if ( ! $in_zone_list ) {
            push @options, '<span class="disabled">New Zone</span>';
        };
    }
    if ( ! $in_zone_list ) {
        push @options, qq[<a href="group_zones_log.cgi?nt_group_id=$group_id">View Zone Log</a>];
    };

    print qq[
<div id="zoneListOptions" class="light_grey_bg side_pad">];

    for my $x ( 1 .. $level ) {
        my $img = $x == $level ? 'dirtree_elbow' : 'transparent';
        print qq[
 <img src="$NicToolClient::image_dir/$img.gif" class="tee" alt="$img">];
    }

    print qq[<img src="$NicToolClient::image_dir/folder_open.gif" class="tee" alt="folder">];

    if ($in_zone_list) {
        print qq[<span class="bold">Zones</span>];
    }
    else {
        print qq[<a href="group_zones.cgi?nt_group_id=$group_id">Zones</a>];
    }

    print qq[
 <span class="float_r pad2">], join( ' | ', @options ), qq[</span>
</div>];
}

sub display_user_list_options {
    my ( $self, $user, $group_id, $level, $in_user_list ) = @_;

    my $q = $self->{'CGI'};

    my @options;
    if ( $user->{'user_create'} ) {
        push @options, qq[<a href="group_users.cgi?nt_group_id=$group_id&amp;new=1">New User</a>]
        unless ($in_user_list);
    }
    else {
        push @options, '<span class="disabled">New User</span>' unless $in_user_list;
    }

    print qq[
<table class="fat">
 <tr class=light_grey_bg>
  <td>
   <table class="no_pad fat">
    <tr>];

    for my $x ( 1 .. $level ) {
        my $img = $x == $level ? 'dirtree_elbow' : 'transparent';
        print qq[
     <td><img src="$NicToolClient::image_dir/$img.gif" class="tee" alt=""></td>];
    }

    print qq[
     <td><img src="$NicToolClient::image_dir/folder_open.gif" alt="folder"></td>];

    if ($in_user_list) {
        print qq[
     <td class="nowrap"><b>Users</b></td>];
    }
    else {
        print qq[
     <td class="nowrap"><a href="group_users.cgi?nt_group_id=$group_id">Users</a></td>];
    }

    print qq[
     <td class="right fat">], join( ' | ', @options ), qq[</td>
    </tr>
   </table>
  </td>
 </tr>
</table>];
}

sub display_zone_options {
    my ( $self, $user, $zone, $level, $in_zone ) = @_;

    my $group = $self->get_group( nt_group_id => $user->{'nt_group_id'} );
    my $q = $self->{'CGI'};
    my $gid = $q->param('nt_group_id');

    my $isdelegate = exists $zone->{'delegated_by_id'} ? 1 : 0;

    my @options;

    #delete option
    if ( $user->{'zone_delete'} && !$isdelegate && !$zone->{'deleted'} ) {
        push @options,
                  qq[<a href="group_zones.cgi?nt_group_id=]
                . $q->param('nt_group_id')
                . qq[&amp;zone_list=$zone->{'nt_zone_id'}&amp;delete=1" onClick="return confirm('Delete $zone->{'zone'} and all associated resource records?');">Delete</a>];
    }
    elsif ( $zone->{'deleted'} ) {
        push @options, qq[<a href="zone.cgi?nt_group_id=$zone->{'nt_group_id'}&amp;nt_zone_id=$zone->{'nt_zone_id'}&amp;edit_zone=1&amp;undelete=1">Undelete</a>];

    }
    elsif ( !$isdelegate ) {
        push @options, '<span style="disabled">Delete</span>';
    }
    elsif ($user->{'zone_delete'}
        && $isdelegate
        && $zone->{'delegate_delete'} )
    {
        push @options, qq[<a href="group_zones.cgi?nt_group_id=$gid&amp;nt_zone_id=$zone->{'nt_zone_id'}&amp;deletedelegate=1" onClick="return confirm('Remove delegation of $zone->{'zone'}?');">Remove Delegation</a>];
    }
    elsif ($isdelegate) {
        push @options, '<span class="disabled">Remove Delegation</span>';
    }

# Move, Delegate, Re-Delegate
    my $win_opts =  qq['width=640,height=480,scrollbars,resizable=yes'];
    if ( $user->{'zone_write'} && !$isdelegate && !$zone->{'deleted'} ) {
        push @options, qq[<a href="javascript:void window.open('move_zones.cgi?obj_list=$zone->{'nt_zone_id'}', 'move_win', $win_opts)">Move</a>] if $group->{'has_children'};
    }
    elsif ( !$isdelegate ) {
        push @options, '<span class="disabled">Move</span>' if $group->{'has_children'};
    }

    if ( $user->{'zone_delegate'} && !$isdelegate && !$zone->{'deleted'} ) {
        push @options, qq[<a href="javascript:void window.open('delegate_zones.cgi?obj_list=$zone->{'nt_zone_id'}', 'delegate_win', $win_opts)">Delegate</a>] if $group->{'has_children'};
    }
    elsif ( !$isdelegate ) {
        push @options, '<span class="disabled">Delegate</span>' if $group->{'has_children'};
    }
    elsif ($user->{'zone_delegate'}
        && $isdelegate
        && $zone->{'delegate_delegate'} )
    {
        push @options, qq[<a href="javascript:void window.open('delegate_zones.cgi?obj_list=$zone->{'nt_zone_id'}', 'delegate_win', $win_opts)">Re-Delegate</a>] if $group->{'has_children'};
    }
    elsif ($isdelegate) {
        push @options, '<span class="disabled">Re-Delegate</span>' if $group->{'has_children'};
    }
    print qq[
<div id="zoneOptions" class="side_pad light_grey_bg">];

    for my $x ( 1 .. $level ) {
        my $img = $x == $level ? 'dirtree_elbow' : 'transparent';
        print qq[\n<img src="$NicToolClient::image_dir/$img.gif" class="tee" alt="$img">];
    }

    if ($isdelegate) {
        my $type = ( $zone->{'pseudo'} ? 'pseudo' : 'delegated' );
        print qq[<img src="$NicToolClient::image_dir/zone-$type.gif" alt="$type">];
    }
    else {
        print qq[<img src="$NicToolClient::image_dir/zone.gif" alt="zone">];
    }

    my $tag = '';
    if (  $isdelegate && !$zone->{'pseudo'} ) {
        my $write = $zone->{'delegate_write'} ? 'write' : 'nowrite';
        $tag = qq[&nbsp;<img src="$NicToolClient::image_dir/perm-$write.gif" alt="permission">];
    };

    if ($in_zone) {
        print qq[<b>$zone->{'zone'}</b>$tag];
    }
    else {
        my $url = "zone.cgi?nt_group_id=$gid&amp;nt_zone_id=$zone->{'nt_zone_id'}";
        print qq[<a href="$url">$zone->{'zone'}</a>$tag];
    }

    print qq[
 <span class="float_r pad2">], join( ' | ', @options ), qq[</span>
</div>];
}

sub display_nameserver_options {
    my ( $self, $user, $group_id, $level, $in_ns_summary ) = @_;


    print qq[
<table id="nameserverOptions" class="fat">
 <tr class=light_grey_bg>
  <td>
   <table class="no_pad fat">
    <tr>];

    for my $x ( 1 .. $level ) {
        my $tee = $x == $level ? 'dirtree_elbow' : 'transparent';
        print qq[
     <td><img src="$NicToolClient::image_dir/$tee.gif" class="tee" alt=""></td>];
    }

    print qq[
     <td><img src="$NicToolClient::image_dir/folder_open.gif" alt="folder"></td>];

    if ($in_ns_summary) {
        print qq[
     <td class="nowrap bold">Nameservers</td>];
    }
    else {
        print qq[
     <td class="nowrap"><a href="group_nameservers.cgi?nt_group_id=$group_id">Nameservers</a></td>];
    }
    print qq[
     <td class="right fat">];

    if ( !$in_ns_summary ) {
        if ( $user->{'nameserver_create'} ) {
            print qq[<a href="group_nameservers.cgi?nt_group_id=$group_id&amp;edit=1">New Nameserver</a>];
        }
        else {
            print qq[<span class="disabled">New Nameserver</class>];
        }
    };

    print
     qq[
     </td>
    </tr>
   </table>
  </td>
 </tr>
</table>];
}

sub paging_fields {
    [   qw(quick_search search_value Search 1_field 1_option 1_value 1_inclusive 2_field 2_option 2_value 2_inclusive
            3_field 3_option 3_value 3_inclusive 4_field 4_option 4_value 4_inclusive 5_field 5_option 5_value 5_inclusive
            change_sortorder 1_sortfield 1_sortmod 2_sortfield 2_sortmod 3_sortfield 3_sortmod start limit page edit_search
            edit_sortorder include_subgroups)
    ];
}

sub prepare_search_params {
    my ( $self, $q, $field_labels, $params, $sort_fields, $default_limit,
        $moreparams )
        = @_;

    $default_limit ||= 20;

    my $search_query = '';

    if ( $q->param('Search') ) {
        foreach ( 1 .. 5 ) {
            if (   $q->param( $_ . '_field' ) ne '--'
                && $q->param( $_ . '_option' ) ne '--'
                && $q->param( $_ . '_value' )  ne '' )
            {
                $params->{'Search'} = 1;

                if ( $_ != 1 ) {
                    $params->{ $_ . '_inclusive' }
                        = $q->param( $_ . '_inclusive' );
                    $params->{'search_query'}
                        .= ' ' . uc( $q->param( $_ . '_inclusive' ) ) . ' ';
                }

                $params->{ $_ . '_field' }  = $q->param( $_ . '_field' );
                $params->{ $_ . '_option' } = $q->param( $_ . '_option' );
                $params->{ $_ . '_value' }  = $q->param( $_ . '_value' );

                $params->{'search_query'}
                    .= $field_labels->{ $q->param( $_ . '_field' ) } . ' '
                    . $q->param( $_ . '_option' ) . " '"
                    . $q->param( $_ . '_value' ) . "'";
            }
        }
    }

    if ( $q->param('change_sortorder') || $params->{'Search'} ) {
        foreach ( 1 .. 3 ) {
            if ( $q->param( $_ . '_sortfield' ) ne '--' ) {
                $sort_fields->{ $q->param( $_ . '_sortfield' ) } = {
                    'order' => $_,
                    'mod'   => $q->param( $_ . '_sortmod' )
                };

                $params->{'Sort'} = 1;
                $params->{ $_ . '_sortfield' } = $q->param( $_ . '_sortfield' );
                $params->{ $_ . '_sortmod' } = $q->param( $_ . '_sortmod' );
            }
        }
    }

    if ( $q->param('quick_search')  && $q->param('search_value') ) {
        $params->{'quick_search'} = 1;
        $params->{'search_value'} = $q->param('search_value');
        $params->{'search_query'} = "'" . $q->param('search_value') . "'";
    }

    $params->{'search_query'} ||= 'ALL';

    $params->{'include_subgroups'} = $q->param('include_subgroups');
    $params->{'exact_match'}       = $q->param('exact_match');

    $params->{'limit'} = $default_limit;
    $params->{'page'}  = $q->param('page');
    $params->{'start'} = $q->param('start');
}

sub display_search_rows {
    my ( $self, $q, $rv, $params, $cgi_name, $state_fields,
        $include_subgroups, $moreparams )
        = @_;

    my $morestr = join( "&amp;", map {"$_=$moreparams->{$_}"} keys %$moreparams );

    return if ( !$q->param('Search')
        && !$q->param('quick_search')
        && ( !$include_subgroups && ( $rv->{'total'} <= $rv->{'limit'} ) )
    );

    my @state_vars;
    foreach ( @{ $self->paging_fields }, @$state_fields ) {
        next if $_ eq 'start';
        next if $_ eq 'limit';
        next if $_ eq 'page';

        push( @state_vars, "$_=" . $q->escape( $q->param($_) ) ) if $q->param($_);
    }

    print qq[
<table id="searchRow" class="fat">
 <tr class="dark_grey_bg">
  <td>
   <form method="post" action="$cgi_name">
    <input type="hidden" name="quick_search" value="Edit">
    <input type="text" name="search_value" size="30">
    <input type="submit" name="quick_search" value="Search">
    ];
    foreach (@$state_fields) {
        print $q->hidden( -name => $_ );
    };
    foreach ( keys %$moreparams ) {
        print $q->hidden( -name => $_, -value => $moreparams->{$_}, -override => 1);
    }
    if ($include_subgroups ) {
        print " &nbsp; &nbsp;",
                $q->checkbox(
                -name    => 'include_subgroups',
                -value   => 1,
                -label   => 'include sub-groups',
                -checked => $NicToolClient::include_subgroups_checked
            );
    };
    print " &nbsp; &nbsp;",
    $q->checkbox(
        -name    => 'exact_match',
        -value   => 1,
        -label   => 'exact match',
        -checked => $NicToolClient::exact_match_checked
        ),
    $q->endform,
    qq[
 </td>
 <td class="right">
  <form method="post" action="$cgi_name">
];

    foreach ( @{ $self->paging_fields }, @$state_fields ) {
        next if $_ eq 'page';
        print $q->hidden( -name => $_ ) if $q->param($_);
    }
    foreach ( keys %$moreparams ) {
        print $q->hidden(
            -name     => $_,
            -value    => $moreparams->{$_},
            -override => 1
        );
    }

    my $state_string = join( '&amp;', @state_vars );
    $state_string .= "&amp;$morestr" if $morestr;

    if ( $rv->{'start'} - $rv->{'limit'} >= 0 ) {
        print qq[<a href="$cgi_name?$state_string&amp;limit=$params->{'limit'}&amp;start=1]
            . qq["><b><<</b></a>&nbsp; ]
            . qq[<a href="$cgi_name?$state_string&amp;limit=$params->{'limit'}&amp;start=]
            . ( $rv->{'start'} - $rv->{'limit'} )
            . qq["><b><</b></a> &nbsp; ];
    }

    my $curpage = $rv->{'end'} % $rv->{'limit'}
                ? int( $rv->{'end'} / $rv->{'limit'} ) + 1
                : $rv->{'end'} / $rv->{'limit'};

    print qq[Page <input type="text" name="page" value="$curpage" size="4"> of $rv->{'total_pages'}];

    if ( $rv->{'end'} + 1 <= $rv->{'total'} ) {
        print qq[ &nbsp; <a href="$cgi_name?$state_string&amp;start=]
            . ( $rv->{'end'} + 1 )
            . "&amp;limit=$params->{'limit'}"
            . qq["><b>></b></a>];
        print qq[ &nbsp; <a href="$cgi_name?$state_string]
            . qq[&amp;page=$rv->{'total_pages'}&amp;limit=$params->{'limit'}]
            . qq["><b>>></b></a>];
    }
    print qq[
   </form>
  </td>
 </tr>
</table>];

    @state_vars = ();
    foreach ( @{ $self->paging_fields }, @$state_fields ) {
        next if ( $_ eq 'edit_search' );
        next if ( $_ eq 'edit_sortorder' );

        push( @state_vars, "$_=" . $q->escape( $q->param($_) ) ) if $q->param($_);
    }

    my $state_string = join( '&amp;', @state_vars );
    $state_string .= "&amp;$morestr" if $morestr;
    my $state_map = join( '&amp;', map( "$_=" . $q->escape( $q->param($_) ), @$state_fields ) );
    $state_map .= "&amp;$morestr" if $morestr;

    my @urls = (
        qq[<a href="$cgi_name?$state_string&amp;edit_search=1">Advanced Search</a>],
        qq[<a href="$cgi_name?$state_string&amp;edit_sortorder=1">Change Sort Order</a>],
    );
    if ( $params->{'search_query'} ne 'ALL' ) {
        push @urls, qq[<a href="$cgi_name?$state_map&amp;$state_map">Browse All</a>];
    };

    print qq[
<div id="searchRowResults" class="dark_grey_bg">
 <span>Search: $params->{'search_query'} found $rv->{'total'} records</span>
 <span class=float_r>] . join(' | ', @urls) . qq[</span>
</div>\n];
}

sub display_sort_options {
    my ( $self, $q, $columns, $labels, $cgi_name, $state_fields,
        $include_subgroups, $moreparams )
        = @_;

    print qq[
<div id="changeSortOrder">
 <form method="post" action="$cgi_name">];

    foreach ( @{ $self->paging_fields }, @$state_fields ) {
        next if $_ =~ /sort/i;
        next if $_ eq 'edit_sortorder';
        next if $_ eq 'start';
        next if $_ eq 'limit';
        next if $_ eq 'page';
        next if ! $q->param($_);
        print $q->hidden( -name => $_ );
    }
    foreach ( keys %$moreparams ) {
        print $q->hidden(
            -name     => $_,
            -value    => $moreparams->{$_},
            -override => 1
        );
    }

    print qq[
<table id="sortOrder" class="fat">
 <tr class=dark_bg>
  <td colspan=2 class="bold">Change Sort Order</td>
 </tr>];
    foreach ( 1 .. 3 ) {
        print qq[
 <tr class=light_grey_bg>
  <td class="nowrap">], ( $_ == 1 ? 'Sort by' : 'Then by' ), qq[</td>
  <td class="fat">],
        $q->popup_menu(
            -name     => $_ . '_sortfield',
            -values   => [ '--', @$columns ],
            -labels   => { '--' => '--', %$labels },
            -override => 1
            ),
            " ",
        $q->popup_menu(
            -name     => $_ . '_sortmod',
            -values   => [ 'Ascending', 'Descending' ],
            -override => 1
        ),
        qq[</td>
 </tr>];
    }
    print qq[
</table>
 <input type="submit" name="change_sortorder" value="Change">
 </form>
 <form method="post" action="$cgi_name">];

    foreach ( @{ $self->paging_fields }, @$state_fields ) {
        next if $_ eq 'edit_sortorder';
        next if ! $q->param($_);
        print $q->hidden( -name => $_ );
    }

    print qq[
  <input type="submit" name="Cancel" value="Cancel">
</form>
</div>
];
}

sub display_advanced_search {
    my ( $self, $q, $columns, $labels, $cgi_name, $state_fields,
        $include_subgroups, $moreparams )
        = @_;

    my @options = (
        'equals', 'contains', 'starts with', 'ends with',
        '<',      '<=',       '>',           '>='
    );

    print $q->start_form( -action => $cgi_name, -method => 'POST' );

    foreach (@$state_fields) {
        print $q->hidden( -name => $_ );
    }

    foreach ( keys %$moreparams ) {
        print $q->hidden(
            -name     => $_,
            -value    => $moreparams->{$_},
            -override => 1
        );
    }

    print qq[
<table id="advancedSearch" class="fat">
 <tr class=dark_bg><td colspan=2 class="bold">Advanced Search</td></tr>
 <tr class=light_grey_bg>
  <td colspan=2>],
        $q->checkbox(
        -name    => 'include_subgroups',
        -value   => 1,
        -label   => 'include sub-groups',
        -checked => $NicToolClient::include_subgroups_checked,
        ),
        "</td>
 </tr>
 <tr class=dark_grey_bg>";

    foreach ( ( 'Inclusive / Exclusive', 'Condition' ) ) {
        print "
  <td class=center> $_ </td>";
    }
    print "
 </tr>";

    foreach ( 1 .. 5 ) {
        print qq[
 <tr class=light_grey_bg>
  <td class=center>],
            (
            $_ == 1 ? '&nbsp;' : $q->radio_group(
                -name     => $_ . '_inclusive',
                -values   => [ 'And', 'Or' ],
                -default  => 'Or',
                -override => 1
            )
            ),
            "</td>\n
        <td>",
            $q->popup_menu(
            -name     => $_ . '_field',
            -values   => [ '--', @$columns ],
            -labels   => { '--' => '- select -', %$labels },
            -override => 1
            ),
        $q->popup_menu(
            -name     => $_ . '_option',
            -values   => \@options,
            -override => 1
        ) . "\n",
        $q->textfield(
            -name     => $_ . '_value',
            -size     => 30,
            -override => 1
            ),
            "</td>\n
        </tr>\n";
    }

    print qq[
</table>
<table id="sortOrderOptional" class="fat">
 <tr class=dark_grey_bg><td colspan=2 class="bold">Sort Order (optional)</td></tr>];
    foreach ( 1 .. 3 ) {
        print "
 <tr class=light_grey_bg>
  <td>", ( $_ == 1 ? 'sort by' : "then by" ), "</td>
  <td>",
            $q->popup_menu(
            -name   => $_ . '_sortfield',
            -values => [ '--', @$columns ],
            -labels => { '--' => '--', %$labels }
            ),
            $q->popup_menu(
            -name   => $_ . '_sortmod',
            -values => [ 'Ascending', 'Descending' ]
            ),
            "</td>
 </tr>";
    }

    print qq[
</table>
<div id="advancedSearchSubmit" class="dark_grey_bg center">
   <input type="submit" name="Search" value="Search" />
</div>],
    $q->endform, 
    qq[
<div id="advancedSearchCancel" class="dark_grey_bg center">],
    $q->startform( -action => $cgi_name, -method => 'POST' );

    foreach ( @{ $self->paging_fields }, @$state_fields ) {
        next if $_ eq 'edit_search';
        next if ! $q->param($_);
        print $q->hidden( -name => $_ );
    }

    print $q->submit('Cancel'),
          $q->endform(), qq[
</div>],
}

sub display_group_list {
    my ( $self, $q, $user, $cgi, $action, $excludeid, $moreparams ) = @_;

    my @columns = qw(group sub_groups);
    $action ||= 'move';
    my %labels = (
        group      => 'Group',
        sub_groups => '*Sub Groups',
    );

    $q->param( 'nt_group_id', $user->{'nt_group_id'} )
        if ! $q->param('nt_group_id');

    my $group = $self->get_group( nt_group_id => $q->param('nt_group_id') );

    if ( ! $group->{'has_children'} ) {
        print qq[<span class="center" style="color:red;"><strong>Group $group->{'name'} has no sub-groups!</strong></span>];
        $q->param( 'nt_group_id', $group->{'parent_group_id'} );
        $group = $self->get_group( nt_group_id => $q->param('nt_group_id') );
    }
    my $include_subgroups = $group->{'has_children'} ? 'sub-groups' : undef;

    my %params = (
        nt_group_id    => $q->param('nt_group_id'),
        start_group_id => $user->{'nt_group_id'}
    );
    
    if ( $user->{'nt_group_id'} == $q->param('nt_group_id') ) {
        $params{'include_parent'} = 1;
    };

    my %sort_fields;
    $self->prepare_search_params( $q, \%labels, \%params, \%sort_fields,
        $NicToolClient::page_length );

    $sort_fields{'group'} = { 'order' => 1, 'mod' => 'Ascending' } if ! %sort_fields;
    my $rv = $self->get_group_subgroups(%params);

    if ( $q->param('edit_sortorder') ) {
        $self->display_sort_options( $q, \@columns, \%labels, $cgi,
            [ 'obj_list', 'nt_group_id' ],
            $include_subgroups, $moreparams );
    };
    if ( $q->param('edit_search') ) {
        $self->display_advanced_search( $q, \@columns, \%labels, $cgi,
            [ 'obj_list', 'nt_group_id' ],
            $include_subgroups, $moreparams );
    };

    return $self->display_error($rv) if $rv->{'error_code'} != 200;

    my $groups = $rv->{'groups'};
    my $map    = $rv->{'group_map'};

    my @state_fields;
    foreach ( @{ $self->paging_fields } ) {
        next if ! $q->param($_);
        push @state_fields, "$_=" . $q->escape( $q->param($_) );
    }
    print qq[
<div id="groupListHeadline" class="dark_grey_bg side_pad">
 <span class="bold">Select the group to $action to.</span>
</div>];

    $self->display_search_rows( $q, $rv, \%params, $cgi,
        [ 'obj_list', 'nt_group_id' ],
        $include_subgroups, $moreparams );

    return if !@$groups;

    print $q->start_form( -action => $cgi, -method => 'POST', -name => 'new' ),
        $q->hidden(
            -name     => 'obj_list',
            -value    => join( ',', $q->param('obj_list') ),
            -override => 1
        );

    foreach ( @{ $self->paging_fields() } ) {
        next if ! $q->param($_);
        print $q->hidden( -name => $_ ) . "\n";
    }
    foreach ( keys %$moreparams ) {
        print $q->hidden( -name => $_, -value => $moreparams->{$_} ) . "\n";
    }

    print qq[
<table id=groupListTable class="fat">
 <tr class=dark_grey_bg>
  <td></td>];

    foreach (@columns) {
        if ( $sort_fields{$_} ) {
            my $sort_dir = uc( $sort_fields{$_}->{'mod'} ) eq 'ASCENDING' ? 'up' : 'down';
            print qq[
  <td class="dark_bg center">
   <div class="no_pad"> $labels{$_} &nbsp; &nbsp; $sort_fields{$_}->{'order'}
     <img src="$NicToolClient::image_dir/$sort_dir.gif" alt="sort">
   </div>
  </td>];
        }
        else {
            print qq[
  <td class=center>$labels{$_}</td>];
            }
        }
    print "
 </tr>";

    my $x = 0;

    foreach my $group (@$groups) {
        my $bgcolor = $x++ % 2 == 0 ? 'light_grey_bg' : 'white_bg';
        print qq[
 <tr class="$bgcolor">
  <td class="width1">];

        if ( $group->{'nt_group_id'} ne $excludeid ) {
            print qq[<input type=radio name=group_list value="$group->{'nt_group_id'}"];
            print qq[ checked] if $x == 1;
            print qq[>];
        };

        print qq[</td>
  <td><img src="$NicToolClient::image_dir/group.gif" alt="group">],
            join(
            ' / ',
            map( qq[<a href="$cgi?nt_group_id=$_->{'nt_group_id'}&amp;obj_list=]
                    . $q->param('obj_list')
                    . (
                    $moreparams
                    ? "&amp;" . join( "&amp;",
                        map {"$_=$moreparams->{$_}"} keys %$moreparams )
                    : ''
                    )
                    . qq[">$_->{'name'}</a>],
                (   @{ $map->{ $group->{'nt_group_id'} } },
                    {   nt_group_id => $group->{'nt_group_id'},
                        name        => $group->{'name'}
                    }
                    ) )
            ),
            "
  </td>
  <td>", ( $group->{'children'} ? $group->{'children'} : 'n/a' ), "</td>
 </tr>";
    }

    print "
</table>";
}

sub redirect_from_log {
    my ( $self, $q ) = @_;

    my $message;

    if ( $q->param('object') eq 'zone' ) {
        my $obj = $self->get_zone(
            nt_group_id => $q->param('nt_group_id'),
            nt_zone_id  => $q->param('obj_id')
        );

        if ( $obj->{'error_code'} != 200 ) {
            $message = $obj;
        }
        else {

#if( $obj->{'deleted'} ) {
#$message = "$obj->{'zone'} is deleted. You are unable to view deleted zones.";
#} else {
            print $q->redirect(
                "zone.cgi?nt_group_id=$obj->{'nt_group_id'}&amp;nt_zone_id=$obj->{'nt_zone_id'}"
            );

            #}
        }
    }
    elsif ( $q->param('object') eq 'nameserver' ) {
        my $obj = $self->get_nameserver(
            nt_group_id      => $q->param('nt_group_id'),
            nt_nameserver_id => $q->param('obj_id')
        );

        if ( $obj->{'error_code'} != 200 ) {
            $message = $obj;
        }
        else {
            if ( $obj->{'deleted'} ) {
                $message = {
                    error_msg =>
                        "Cannot view Nameserver '$obj->{'name'}': the object has been deleted.",
                    error_desc => 'Object is deleted',
                    error_code => 'client'
                };
            }
            else {
                print $q->redirect(
                    "group_nameservers.cgi?nt_group_id=$obj->{'nt_group_id'}&amp;nt_nameserver_id=$obj->{'nt_nameserver_id'}&amp;edit=1"
                );
            }
        }
    }
    elsif ( $q->param('object') eq 'user' ) {
        my $obj = $self->get_user(
            nt_group_id => $q->param('nt_group_id'),
            nt_user_id  => $q->param('obj_id')
        );

        if ( $obj->{'error_code'} != 200 ) {
            $message = $obj;
        }
        else {
            if ( $obj->{'deleted'} ) {
                $message = {
                    error_msg =>
                        "Cannot view User '$obj->{'username'}': the object has been deleted.",
                    error_desc => 'Object is deleted',
                    error_code => 'client'
                };
            }
            else {
                print $q->redirect(
                    "user.cgi?nt_group_id=$obj->{'nt_group_id'}&amp;nt_user_id=$obj->{'nt_user_id'}"
                );
            }
        }
    }
    elsif ( $q->param('object') eq 'zone_record' ) {
        my $obj = $self->get_zone_record(
            nt_zone_record_id => $q->param('obj_id') );

        if ( $obj->{'error_code'} != 200 ) {
            $message = $obj;
        }
        else {
            if ( $obj->{'deleted'} ) {
                $message = {
                    error_msg =>
                        "Cannot view Zone Record '$obj->{'name'}': the object has been deleted.",
                    error_desc => 'Object is deleted',
                    error_code => 'client'
                };
            }
            else {
                print $q->redirect( "zone.cgi?nt_group_id="
                        . $q->param('nt_group_id')
                        . "&amp;nt_zone_id=$obj->{'nt_zone_id'}&amp;nt_zone_record_id=$obj->{'nt_zone_record_id'}&amp;edit_record=1"
                );
            }
        }
    }
    elsif ( $q->param('object') eq 'group' ) {
        my $obj = $self->get_group( nt_group_id => $q->param('obj_id') );

        if ( $obj->{'error_code'} != 200 ) {
            $message = $obj;
        }
        else {
            if ( $obj->{'deleted'} ) {
                $message = {
                    error_msg =>
                        "Cannot view Group '$obj->{'name'}': the object has been deleted.",
                    error_desc => 'Object is deleted',
                    error_code => 'client'
                };
            }
            else {
                print $q->redirect(
                    "group.cgi?nt_group_id=$obj->{'nt_group_id'}");
            }
        }
    }
    else {
        $message = {
            error_msg  => "Unable to find object",
            error_desc => 'Not Found',
            error_code => 'client'
        };
    }

    return $message;
}

sub display_move_javascript {
    my ( $self, $cgi, $name ) = @_;
    print <<ENDJS;
\n<script>
function selectAllorNone(group, action) {
    if(group.length){
        for( var x = 0; x < group.length; x++ ) {
                group[x].checked = action;
        }
    }else{
        group.checked=action;
    }
}
function open_move(list) {
    var obj_list = new Array();
    if( list.length ) {
            var y = 0;
            for( x = 0; x < list.length; x++ ) {
                    if( list[x].checked ) obj_list[y++] = list[x].value;
            }
    } else {
            if( list.checked ) obj_list[0] = list.value;
    }
    if( obj_list.length > 0 ) {
            newwin = window.open('$cgi?obj_list=' + obj_list.join(','), 'move_win', 'width=640,height=480,scrollbars,resizable=yes');
            newwin.opener = self;
    } else {
            alert('Select at least one $name');
    }
}
</script>
ENDJS
}

sub display_delegate_javascript {
    my ( $self, $cgi, $name ) = @_;
    print <<ENDJS;
<script>
function open_delegate(list) {
    var obj_list = new Array();
    if( list.length ) {
            var y = 0;
            for( x = 0; x < list.length; x++ ) {
                    if( list[x].checked ) obj_list[y++] = list[x].value;
            }
    } else {
            if( list.checked ) obj_list[0] = list.value;
    }
    if( obj_list.length > 0 ) {
            newwin = window.open('$cgi?obj_list=' + obj_list.join(','), 'move_win', 'width=640,height=480,scrollbars,resizable=yes');
            newwin.opener = self;
    } else {
            alert('Select at least one $name');
    }
}
</script>
ENDJS
}

sub error_message {
    my ( $self, $code, $msg ) = @_;
    $code ||= 700;
    my $errs = {
        200 => ['OK'],

        300 => ['Sanity Error'],
        301 => [
            'Some Required Parameters Missing',
            "Data may be missing from a previous operation.  Please click 'Back' on your browser and try again."
        ],
        302 => ['Some parameters were invalid'],

        403 => [
            'Invalid Username and/or password',
            $NicToolClient::generic_error_message
        ],
        404 => [
            'Access Permission Denied',
            $NicToolClient::generic_error_message
        ],

        #405=>'Delegation Permission denied: ',
        #406=>'Creation Permission denied: ',
        #407=>'Delegate Access Permission denied: ',

        500 => [
            'Unknown Action Requested',
            $NicToolClient::generic_error_message
        ],
        501 => [
            'Client-Server Connectivity Error',
            $NicToolClient::generic_error_message
        ],
        502 =>
            [ 'XML-RPC Data Error', $NicToolClient::generic_error_message ],
        503 => [
            'Method has been deprecated',
            $NicToolClient::generic_error_message
        ],
        505 =>
            [ 'Database Query Error', $NicToolClient::generic_error_message ],
        507 => [ 'Internal Error', $NicToolClient::generic_error_message ],
        508 => [ 'Internal Error', $NicToolClient::generic_error_message ],
        510 => [
            'Incorrect Protocol Version Number',
            'You probably need to upgrade the client to connect to the chosen server.'
        ],

        600 => ['Failed to Complete Request'],
        601 => ['Object Not Found'],

        700    => [ 'Unknown Error', $NicToolClient::generic_error_message ],
        client => ['Client Error'],
    };

    my $res = $errs->{$code};
    $res ||= $errs->{700};

    #$res.=$msg if $msg;
    return $res;
}

sub display_nice_message {
    my ( $self, $message, $title, $explain ) = @_;
    my @msgs = split( /\bAND\b/, $message );
    $message = qq( <li style="color: blue;"> )
        . join( qq(<br>\n<li style="color: blue;"> ), @msgs )
        . '<br>';

    print qq{
<table id="niceMessage" class="center fat">
  <tr><td class="left dark_bg bold">$title</td></tr>
  <tr><td class="left light_grey_bg">$message<p>$explain</td></tr>
  <tr><td>&nbsp;</td></tr>
</table>
    };
    return 0;
}

sub display_nice_error {
    my ( $self, $error, $actionmsg, $back ) = @_;
    my ( $message, $explain ) = @{ $self->error_message( $error->{'error_code'} ) };
    my $err = $error->{'error_desc'} || 'Error';
    $actionmsg = ": " . $actionmsg if $actionmsg;

    my $errmsg = $error->{'error_msg'};
    my @msgs = split( /\bAND\b/, $errmsg );
    $errmsg = "<div class=error><ul>\n";
    foreach ( @msgs ) {
        $errmsg .= qq[<li>$_</li>\n];
    };
    $errmsg .= qq[</ul>\n</div>];

    my $bb = $back ? '<form><input type=submit value="Back" onClick="javascript:history.go(-1)"></form>'
           : '&nbsp;';

    print qq[<br>\n
<table id="errorMessage" class="fat center">
 <tr><td class="left error_bg"><strong>$message</strong>$actionmsg</td></tr>
 <tr><td class="left light_grey_bg">$errmsg<p>$explain</p></td></tr>
 <tr><td class="right dark_grey_bg dark">$bb ($error->{'error_code'})</td></tr>
</table>];

    warn "Client error: $error->{'error_code'}: $error->{'error_msg'}: " . join( ":", caller );
    return 0;
}

sub display_error {
    my ( $self, $error ) = @_;

    print qq[ <center class="error"><b>$error->{'error_msg'}</b></center> ];

    warn
        "Client error: $error->{'error_code'}: $error->{'error_msg'}: $error->{'error_desc'} "
        . join( ":", caller );
    return 0;
}

sub zone_record_template_list {

    # the templates available in zone_record_template
    return qw( none basic wildcard basic-spf wildcard-spf );
}

sub zone_record_template {
    my ( $self, $vals ) = @_;

    my $zone     = $vals->{'zone'};
    my $id       = $vals->{'nt_zone_id'};
    my $template = $vals->{'template'};
    my $newip    = $vals->{'newip'};
    my $mailip   = $vals->{'mailip'} || $newip;
    my $debug    = $vals->{'debug'};

    return 0 if ( $template eq "none" || $template eq "" );

    print "zone_record_template: $id, $zone, $template\n" if $debug;

    #               basic template
    #       zone.com.        IN     A      xx.xxx.xx.xx
    #       zone.com.        IN  10 MX     zone.com.
    #       mail             IN     A      xx.xxx.xx.xx
    #       www.zone.com.    IN     CNAME  zone.com.

    my %record1 = (
        nt_zone_id => $id,
        name       => "$zone.",
        type       => "A",
        address    => $newip
    );
    my %record2 = (
        nt_zone_id => $id,
        name       => "mail",
        type       => "A",
        address    => $mailip
    );
    my %record3 = (
        nt_zone_id => $id,
        name       => "www",
        type       => "CNAME",
        address    => "$zone."
    );
    my %record4 = (
        nt_zone_id => $id,
        name       => "$zone.",
        type       => "MX",
        address    => "mail.$zone.",
        weight     => "10"
    );
    my @zr = ( \%record1, \%record2, \%record3, \%record4 );

    if ( $template eq "wildcard" ) {

        #          template Basic with hostname wildcard
        #       zone.com.        IN     A      NN.NNN.NN.NN
        #       zone.com.        IN  10 MX     mail.zone.com.
        #       mail             IN     A      NN.NNN.NN.NN
        #       *.zone.com.      IN     CNAME  zone.com.
        #
        %record3 = (
            nt_zone_id => $id,
            name       => "*",
            type       => "CNAME",
            address    => "$zone."
        );
        @zr = ( \%record1, \%record2, \%record3, \%record4 );
    }
    elsif ( $template eq "basic-spf" ) {
        my %record5 = (
            nt_zone_id => $id,
            name       => "$zone.",
            type       => "TXT",
            address    => "v=spf1 a mx -all"
        );
        my %record6 = (
            nt_zone_id => $id,
            name       => "$zone.",
            type       => "SPF",
            address    => "v=spf1 a mx -all"
        );
        @zr = ( \%record1, \%record2, \%record3, \%record4, \%record5, \%record6 );
    }
    elsif ( $template eq "wildcard-spf" ) {
        %record3 = (
            nt_zone_id => $id,
            name       => "*",
            type       => "CNAME",
            address    => "$zone."
        );
        my %record5 = (
            nt_zone_id => $id,
            name       => "$zone.",
            type       => "TXT",
            address    => "v=spf1 a mx -all"
        );
        my %record6 = (
            nt_zone_id => $id,
            name       => "$zone.",
            type       => "SPF",
            address    => "v=spf1 a mx -all"
        );
        @zr = ( \%record1, \%record2, \%record3, \%record4, \%record5, \%record6 );
    }

    return \@zr;
}

sub refresh_nav {
    my $self = shift;
    print "<script>\nparent.nav.location = parent.nav.location;\n</script>";
}

sub AUTOLOAD {
    my $self = shift;

    my $type = ref($self);
    my $name = $AUTOLOAD;

    unless ( ref($self) ) {
        warn "$type" . "::AUTOLOAD $self is not an object -- (params: @_)\n";
        return undef;
    }

    return if $name =~ /::DESTROY$/;

    $name =~ s/.*://;    # strip fully-qualified portion

    if ( $name =~ /^(get_|new_|edit_|delegate_|save_|delete_|move_)/i ) {
        return $self->{'nt_server_obj'}->send_request(
            action => "$name",
            @_, nt_user_session => $self->{'CGI'}->cookie('NicTool')
        );
    }
    else {
        return { error_code => '900', error_msg => 'Invalid action' };
    }
}

1;
__END__

=head1 SYNOPSIS

Methods used by the CGI files in the htdocs directory

=cut
