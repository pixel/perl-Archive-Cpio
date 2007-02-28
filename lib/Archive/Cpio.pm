package Archive::Cpio;

our $VERSION = 0.02;

=head1 NAME

Archive::Cpio - module for manipulations of cpio archives

=head1 SYNOPSIS     

    use Archive::Cpio;

    # simple example removing entry "foo"

    while (my $e = Archive::Cpio::read_one(\*STDIN)) {
         if ($e->{name} ne 'foo') {
               Archive::Cpio::write_one(\*STDOUT, $e);
         }
    }
    Archive::Cpio::write_trailer(\*STDOUT);

=head1 DESCRIPTION

Archive::Cpio provides a few functions to read and write cpio files.

=cut

my $NEWC_MAGIC = 0x070701;
my $CRC_MAGIC  = 0x070702;
my $TRAILER    = 'TRAILER!!!';
my $BLOCK_SIZE = 512;

my @HEADER = (
    magic => 6,
    inode => 8,
    mode => 8,
    uid => 8,
    gid => 8,
    nlink => 8,
    mtime => 8,
    datasize => 8,
    devMajor => 8,
    devMinor => 8,
    rdevMajor => 8,
    rdevMinor => 8,
    namesize => 8,
    checksum => 8,
);


=head2 Archive::Cpio::read_all($filehandle)

Returns a list of entries

=cut

sub read_all {
    my ($F) = @_;
    my @l;
    while (my $entry = read_one($F)) {
	push @l, $entry;
    }
    \@l;
}

=head2 Archive::Cpio::write_all($filehandle, $list_ref)

Writes the entries and the trailer

=cut

sub write_all {
    my ($F, $l) = @_;

    write_one($F, $_) foreach @$l;
    write_trailer($F);
}

=head2 Archive::Cpio::read_all($filehandle)

Returns the next entry

=cut

sub read_one {
    my ($F) = @_;
    my $entry = read_one_header($F);

    $entry->{name} = read_or_die($F, $entry->{namesize}, 'name');
    $entry->{name} =~ s/\0$//;

    $entry->{name} ne $TRAILER or return;
    read_or_die($F, padding(4, $entry->{namesize} + 2), 'padding');

    $entry->{data} = read_or_die($F, $entry->{datasize}, 'data');
    read_or_die($F, padding(4, $entry->{datasize}), 'padding');

    cleanup_entry($entry);

    $entry;
}

sub read_one_header {
    my ($F) = @_;

    my %h;
    my @header = @HEADER;
    while (@header) {
	my $field = shift @header;
	my $size =  shift @header;
	$h{$field} = read_or_die($F, $size, $field);
	$h{$field} =~ /^[0-9A-F]*$/si or die "bad header value $h{$field}\n";
	$h{$field} = hex $h{$field};
    }
    $h{magic} == $NEWC_MAGIC || $h{magic} == $CRC_MAGIC or die "bad magic ($h{magic})\n";

    \%h;
}

=head2 Archive::Cpio::write_one($filehandle, $entry)

Writes an entry (beware, a valid cpio needs a trailer using C<write_trailer>)

=cut

sub write_one {
    my ($F, $entry) = @_;

    $entry->{magic} = $NEWC_MAGIC;
    $entry->{namesize} = length($entry->{name}) + 1;
    $entry->{datasize} = length($entry->{data});

    write_or_die($F, pack_header($entry) .
		     $entry->{name} . "\0" .
		     "\0" x padding(4, $entry->{namesize} + 2));
    write_or_die($F, $entry->{data});
    write_or_die($F, "\0" x padding(4, $entry->{datasize}));

    cleanup_entry($entry);
}

=head2 Archive::Cpio::write_trailer($filehandle)

Writes an entry (beware, a valid cpio needs a trailer using C<write_trailer>)

=cut

sub write_trailer {
    my ($F) = @_;

    write_one($F, { name => $TRAILER, data => '', nlink => 1 });
    write_or_die($F, "\0" x padding($BLOCK_SIZE, tell($F)));
}

sub cleanup_entry {
    my ($entry) = @_;

    foreach ('datasize', 'namesize', 'magic') {
	delete $entry->{$_};
    }
}

sub padding {
    my ($nb, $offset) = @_;

    my $align = $offset % $nb;
    $align ? $nb - $align : 0;
}

sub pack_header {
    my ($h) = @_;

    my $packed = '';
    my @header = @HEADER;
    while (@header) {
	my $field = shift @header;
	my $size =  shift @header;

	$packed .= sprintf("%0${size}X", $h->{$field} || 0);
    }
    $packed;
}

sub read_or_die {
    my ($F, $size, $name) = @_;
    $size or return;

    my $tmp;
    if ($size !~ /^\d+$/) {
	die "bad size $size\n";
    }
    read($F, $tmp, $size) == $size or die "unexpected end of file while reading $name (got $tmp)\n";
    $tmp;
}
sub write_or_die {
    my ($F, $val) = @_;
    print $F $val or die "writing failed: $!\n";
}

=head1 AUTHOR

Pascal Rigaux <pixel@mandriva.com>

=cut 
