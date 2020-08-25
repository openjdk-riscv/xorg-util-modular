#!/bin/bash
#
#		Creates and upload a git module tarball
#
# Note on portability:
# This script is intended to run on any platform supported by X.Org.
# Basically, it should be able to run in a Bourne shell.
#
#

export LC_ALL=en_US.UTF-8


#------------------------------------------------------------------------------
#			Function: check_local_changes
#------------------------------------------------------------------------------
#
check_local_changes() {
    git diff --quiet HEAD > /dev/null 2>&1
    if [ $? -ne 0 ]; then
	echo ""
	echo "Uncommitted changes found. Did you forget to commit? Aborting."
	echo ""
	echo "You can perform a 'git stash' to save your local changes and"
	echo "a 'git stash apply' to recover them after the tarball release."
	echo "Make sure to rebuild and run 'make distcheck' again."
	echo ""
	echo "Alternatively, you can clone the module in another directory"
	echo "and run ./configure. No need to build if testing was finished."
	echo ""
	return 1
    fi
    return 0
}

#------------------------------------------------------------------------------
#			Function: check_option_args
#------------------------------------------------------------------------------
#
# perform sanity checks on cmdline args which require arguments
# arguments:
#   $1 - the option being examined
#   $2 - the argument to the option
# returns:
#   if it returns, everything is good
#   otherwise it exit's
check_option_args() {
    option=$1
    arg=$2

    # check for an argument
    if [ x"$arg" = x ]; then
	echo ""
	echo "Error: the '$option' option is missing its required argument."
	echo ""
	usage
	exit 1
    fi

    # does the argument look like an option?
    echo $arg | $GREP "^-" > /dev/null
    if [ $? -eq 0 ]; then
	echo ""
	echo "Error: the argument '$arg' of option '$option' looks like an option itself."
	echo ""
	usage
	exit 1
    fi
}

#------------------------------------------------------------------------------
#			Function: check_gpgkey
#------------------------------------------------------------------------------
#
# check if the gpg key provided is known/available
# arguments:
#   $1 - the gpg key
# returns:
#   if it returns, everything is good
#   otherwise it exit's
check_gpgkey() {
    arg=$1

    $GPG --list-keys "$arg" &>/dev/null
    if [ $? -ne 0 ]; then
	echo ""
	echo "Error: the argument '$arg' is not a known gpg key."
	echo ""
	usage
	exit 1
    fi
}

#------------------------------------------------------------------------------
#			Function: check_modules_specification
#------------------------------------------------------------------------------
#
check_modules_specification() {

if [ x"$MODFILE" = x ]; then
    if [ x"${INPUT_MODULES}" = x ]; then
	echo ""
	echo "Error: no modules specified (blank command line)."
	usage
	exit 1
    fi
fi

}

#------------------------------------------------------------------------------
#			Function: generate_announce
#------------------------------------------------------------------------------
#
generate_announce()
{
    cat <<RELEASE
Subject: [ANNOUNCE] $pkg_name $pkg_version
To: $list_to
Cc: $list_cc

`git log --no-merges "$tag_range" | git shortlog`

git tag: $tag_name

RELEASE

    for tarball in $tarbz2 $targz $tarxz; do
	tarball=`basename $tarball`
	cat <<RELEASE
https://$host_current/$section_path/$tarball
SHA256: `$SHA256SUM $tarball`
SHA512: `$SHA512SUM $tarball`
PGP:  https://${host_current}/${section_path}/${tarball}.sig

RELEASE
    done
}

#------------------------------------------------------------------------------
#			Function: read_modfile
#------------------------------------------------------------------------------
#
# Read the module names from the file and set a variable to hold them
# This will be the same interface as cmd line supplied modules
#
read_modfile() {

    if [ x"$MODFILE" != x ]; then
	# Make sure the file is sane
	if [ ! -r "$MODFILE" ]; then
	    echo "Error: module file '$MODFILE' is not readable or does not exist."
	    exit 1
	fi
	# read from input file, skipping blank and comment lines
	while read line; do
	    # skip blank lines
	    if [ x"$line" = x ]; then
		continue
	    fi
	    # skip comment lines
	    if echo "$line" | $GREP -q "^#" ; then
		continue;
	    fi
	    INPUT_MODULES="$INPUT_MODULES $line"
	done <"$MODFILE"
    fi
    return 0
}

#------------------------------------------------------------------------------
#			Function: print_epilog
#------------------------------------------------------------------------------
#
print_epilog() {

    epilog="========  Successful Completion"
    if [ x"$NO_QUIT" != x ]; then
	if [ x"$failed_modules" != x ]; then
	    epilog="========  Partial Completion"
	fi
    elif [ x"$failed_modules" != x ]; then
	epilog="========  Stopped on Error"
    fi

    echo ""
    echo "$epilog `date`"

    # Report about modules that failed for one reason or another
    if [ x"$failed_modules" != x ]; then
	echo "	List of failed modules:"
	for mod in $failed_modules; do
	    echo "	$mod"
	done
	echo "========"
	echo ""
    fi
}

#------------------------------------------------------------------------------
#			Function: process_modules
#------------------------------------------------------------------------------
#
# Loop through each module to release
# Exit on error if --no-quit was not specified
#
process_modules() {
    for MODULE_RPATH in ${INPUT_MODULES}; do
	if ! process_module ; then
	    echo "Error: processing module \"$MODULE_RPATH\" failed."
	    failed_modules="$failed_modules $MODULE_RPATH"
	    if [ x"$NO_QUIT" = x ]; then
		print_epilog
		exit 1
	    fi
	fi
    done
}

#------------------------------------------------------------------------------
#			Function: get_section
#------------------------------------------------------------------------------
# Code 'return 0' on success
# Code 'return 1' on error
# Sets global variable $section
get_section() {
    local module_url
    local full_module_url

    # Obtain the git url in order to find the section to which this module belongs
    full_module_url=`git config --get remote.$remote_name.url | sed 's:\.git$::'`
    if [ $? -ne 0 ]; then
	echo "Error: unable to obtain git url for remote \"$remote_name\"."
	return 1
    fi

    # The last part of the git url will tell us the section. Look for xorg first
    module_url=`echo "$full_module_url" | $GREP -o "xorg/.*"`
    if [ $? -eq 0 ]; then
	module_url=`echo $module_url | rev | cut -d'/' -f1,2 | rev`
    else
	# The look for mesa, xcb, etc...
	module_url=`echo "$full_module_url" | $GREP -o -e "mesa/.*" -e "/xcb/.*" -e "/xkeyboard-config" -e "/nouveau/xf86-video-nouveau" -e "/libevdev" -e "/wayland/.*" -e "/evemu" -e "/libinput"`
	if [ $? -eq 0 ]; then
	     module_url=`echo $module_url | cut -d'/' -f2,3`
	else
	    echo "Error: unable to locate a valid project url from \"$full_module_url\"."
	    echo "Cannot establish url as one of xorg, mesa, xcb, xf86-video-nouveau, xkeyboard-config or wayland"
	    cd $top_src
	    return 1
	fi
    fi

    # Find the section (subdirs) where the tarballs are to be uploaded
    # The module relative path can be app/xfs, xserver, or mesa/drm for example
    section=`echo $module_url | cut -d'/' -f1`
    if [ $? -ne 0 ]; then
	echo "Error: unable to extract section from $module_url first field."
	return 1
    fi

    if [ x"$section" = xmesa ]; then
	section=`echo $module_url | cut -d'/' -f2`
	if [ $? -ne 0 ]; then
	    echo "Error: unable to extract section from $module_url second field."
	    return 1
	elif [ x"$section" != xdrm ] &&
	     [ x"$section" != xmesa ] &&
	     [ x"$section" != xglu ] &&
	     [ x"$section" != xdemos ]; then
	    echo "Error: section $section is not supported, only libdrm, mesa, glu and demos are."
	    return 1
	fi
    fi

    if [ x"$section" = xwayland -o x"$section" = xxorg ]; then
	section=`echo $module_url | cut -d'/' -f2`
	if [ $? -ne 0 ]; then
	    echo "Error: unable to extract section from $module_url second field."
	    return 1
	fi
    fi

    return 0
}

#                       Function: sign_or_fail
#------------------------------------------------------------------------------
#
# Sign the given file, if any
# Output the name of the signature generated to stdout (all other output to
# stderr)
# Return 0 on success, 1 on fail
#
sign_or_fail() {
    if [ -n "$1" ]; then
	sig=$1.sig
	rm -f $sig
	$GPG -b $GPGKEY $1 1>&2
	if [ $? -ne 0 ]; then
	    echo "Error: failed to sign $1." >&2
	    return 1
	fi
	echo $sig
    fi
    return 0
}

#------------------------------------------------------------------------------
#			Function: process_module
#------------------------------------------------------------------------------
# Code 'return 0' on success to process the next module
# Code 'return 1' on error to process next module if invoked with --no-quit
#
process_module() {

    local use_autogen=0
    local use_meson=0

    top_src=`pwd`
    echo ""
    echo "========  Processing \"$top_src/$MODULE_RPATH\""

    # This is the location where the script has been invoked
    if [ ! -d $MODULE_RPATH ] ; then
	echo "Error: $MODULE_RPATH cannot be found under $top_src."
	return 1
    fi

    # Change directory to be in the git module
    cd $MODULE_RPATH
    if [ $? -ne 0 ]; then
	echo "Error: failed to cd to $MODULE_RPATH."
	return 1
    fi

    # ----- Now in the git module *root* directory ----- #

    # Check that this is indeed a git module
    # Don't assume that $(top_srcdir)/.git is a directory. It may be
    # a gitlink file if $(top_srcdir) is a submodule checkout or a linked
    # worktree.
    if [ ! -e .git ]; then
	echo "Error: there is no git module here: `pwd`"
	return 1
    fi

    # Determine what is the current branch and the remote name
    current_branch=`git branch | $GREP "\*" | sed -e "s/\* //"`
    remote_name=`git config --get branch.$current_branch.remote`
    remote_branch=`git config --get branch.$current_branch.merge | cut -d'/' -f3,4`
    echo "Info: working off the \"$current_branch\" branch tracking the remote \"$remote_name/$remote_branch\"."

    # Obtain the section
    get_section
    if [ $? -ne 0 ]; then
	cd $top_src
	return 1
    fi

    # Check for uncommitted/queued changes.
    check_local_changes
    if [ $? -ne 0 ]; then
	return 1
    fi

    if [ -f autogen.sh ]; then
	use_autogen=1
    elif [ -f meson.build ]; then
	use_meson=1
        which jq >& /dev/null
        if [ $? -ne 0 ]; then
            echo "Cannot find required jq(1) to parse project metadata"
            return 1
        fi
    else
	echo "Cannot find autogen.sh or meson.build"
	return 1
    fi

    if [ $use_autogen != 0 ]; then
	# If AC_CONFIG_AUX_DIR isn't set, libtool will search down to ../.. for
	# install-sh and then just guesses that's the aux dir, dumping
	# config.sub and other files into that directory. make distclean then
	# complains about leftover files. So let's put our real module dir out
	# of reach of libtool.
	#
	# We use release/$section/$build_dir because git worktree will pick the
	# last part as branch identifier, so it needs to be random to avoid
	# conflicts.
	build_dir="release/$section"
	mkdir -p "$build_dir"

	# Create tmpdir for the release
	build_dir=`mktemp -d -p "$build_dir" build.XXXXXXXXXX`
	if [ $? -ne 0 ]; then
	    echo "Error: could not create a temporary directory for the release"
	    echo "Do you have coreutils' mktemp ?"
	    return 1
	fi

	# Worktree removal is intentionally left to the user, due to:
	#  - currently we cannot select only one worktree to prune
	#  - requires to removal of $build_dir which might contradict with the
	# user decision to keep some artefacts like tarballs or other
	echo "Info: creating new git worktree."
	git worktree add $build_dir
	if [ $? -ne 0 ]; then
	    echo "Error: failed to create a git worktree."
	    cd $top_src
	    return 1
	fi

	cd $build_dir
	if [ $? -ne 0 ]; then
	    echo "Error: failed to cd to $MODULE_RPATH/$build_dir."
	    cd $top_src
	    return 1
	fi

	echo "Info: running autogen.sh"
	./autogen.sh >/dev/null

	if [ $? -ne 0 ]; then
	    echo "Error: failed to configure module."
	    cd $top_src
	    return 1
	fi

	# Run 'make dist/distcheck' to ensure the tarball matches the git module content
	# Important to run make dist/distcheck before looking in Makefile, may need to reconfigure
	echo "Info: running \"make $MAKE_DIST_CMD\" to create tarballs:"
	${MAKE} $MAKEFLAGS $MAKE_DIST_CMD > /dev/null
	if [ $? -ne 0 ]; then
	    echo "Error: \"$MAKE $MAKEFLAGS $MAKE_DIST_CMD\" failed."
	    cd $top_src
	    return 1
	fi

	# Find out the tarname from the makefile
	pkg_name=`$GREP '^PACKAGE = ' Makefile | sed 's|PACKAGE = ||'`
	pkg_version=`$GREP '^VERSION = ' Makefile | sed 's|VERSION = ||'`
	tar_root="."
	announce_dir=$tar_root
    else
	# meson sets up ninja dist so we don't have to do worktrees and it
	# has the builddir enabled by default
	build_dir="builddir"
	meson $build_dir
	if [ $? -ne 0 ]; then
	    echo "Error: failed to configure module."
	    cd $top_src
	    return 1
	fi

	echo "Info: running \"ninja dist\" to create tarball:"
	ninja -C $build_dir dist
	if [ $? -ne 0 ]; then
	    echo "Error: ninja dist failed"
	    cd $top_src
	    return 1
	fi

	# Find out the package name from the meson.build file
	pkg_name=$(meson introspect $build_dir --projectinfo | jq -r .descriptive_name)
	pkg_version=$(meson introspect $build_dir --projectinfo | jq -r .version)
	tar_root="$build_dir/meson-dist"
	announce_dir=$tar_root
    fi

    tar_name="$pkg_name-$pkg_version"
    targz="$tar_root/$tar_name.tar.gz"
    tarbz2="$tar_root/$tar_name.tar.bz2"
    tarxz="$tar_root/$tar_name.tar.xz"

    [ -e $targz ] && ls -l $targz || unset targz
    [ -e $tarbz2 ] && ls -l $tarbz2 || unset tarbz2
    [ -e $tarxz ] && ls -l $tarxz || unset tarxz

    if [ -z "$targz" -a -z "$tarbz2" -a -z "$tarxz" ]; then
	echo "Error: no compatible tarballs found."
	cd $top_src
	return 1
    fi

    # wayland/weston/libinput tag with the version number only
    tag_name="$tar_name"
    if [ x"$section" = xwayland ] ||
       [ x"$section" = xweston ] ||
       [ x"$section" = xlibinput ]; then
	tag_name="$pkg_version"
    fi

    # evemu tag with the version number prefixed by 'v'
    if [ x"$section" = xevemu ]; then
        tag_name="v$pkg_version"
    fi

    gpgsignerr=0
    siggz="$(sign_or_fail ${targz})"
    gpgsignerr=$((${gpgsignerr} + $?))
    sigbz2="$(sign_or_fail ${tarbz2})"
    gpgsignerr=$((${gpgsignerr} + $?))
    sigxz="$(sign_or_fail ${tarxz})"
    gpgsignerr=$((${gpgsignerr} + $?))
    if [ ${gpgsignerr} -ne 0 ]; then
        echo "Error: unable to sign at least one of the tarballs."
        cd $top_src
        return 1
    fi

    # Obtain the top commit SHA which should be the version bump
    # It should not have been tagged yet (the script will do it later)
    local_top_commit_sha=`git  rev-list --max-count=1 HEAD`
    if [ $? -ne 0 ]; then
	echo "Error: unable to obtain the local top commit id."
	cd $top_src
	return 1
    fi

    # Check that the top commit looks like a version bump
    git diff --unified=0 HEAD^ | $GREP -F $pkg_version >/dev/null 2>&1
    if [ $? -ne 0 ]; then
	# Wayland repos use  m4_define([wayland_major_version], [0])
	git diff --unified=0 HEAD^ | $GREP -E "(major|minor|micro)_version" >/dev/null 2>&1
	if [ $? -ne 0 ]; then
	    echo "Error: the local top commit does not look like a version bump."
	    echo "       the diff does not contain the string \"$pkg_version\"."
	    local_top_commit_descr=`git log --oneline --max-count=1 $local_top_commit_sha`
	    echo "       the local top commit is: \"$local_top_commit_descr\""
	    cd $top_src
	    return 1
	fi
    fi

    # Check that the top commit has been pushed to remote
    remote_top_commit_sha=`git  rev-list --max-count=1 $remote_name/$remote_branch`
    if [ $? -ne 0 ]; then
	echo "Error: unable to obtain top commit from the remote repository."
	cd $top_src
	return 1
    fi
    if [ x"$remote_top_commit_sha" != x"$local_top_commit_sha" ]; then
	echo "Error: the local top commit has not been pushed to the remote."
	local_top_commit_descr=`git log --oneline --max-count=1 $local_top_commit_sha`
	echo "       the local top commit is: \"$local_top_commit_descr\""
	cd $top_src
	return 1
    fi

    # If a tag exists with the tar name, ensure it is tagging the top commit
    # It may happen if the version set in configure.ac has been previously released
    tagged_commit_sha=`git  rev-list --max-count=1 $tag_name 2>/dev/null`
    if [ $? -eq 0 ]; then
	# Check if the tag is pointing to the top commit
	if [ x"$tagged_commit_sha" != x"$remote_top_commit_sha" ]; then
	    echo "Error: the \"$tag_name\" already exists."
	    echo "       this tag is not tagging the top commit."
	    remote_top_commit_descr=`git log --oneline --max-count=1 $remote_top_commit_sha`
	    echo "       the top commit is: \"$remote_top_commit_descr\""
	    local_tag_commit_descr=`git log --oneline --max-count=1 $tagged_commit_sha`
	    echo "       tag \"$tag_name\" is tagging some other commit: \"$local_tag_commit_descr\""
	    cd $top_src
	    return 1
	else
	    echo "Info: module already tagged with \"$tag_name\"."
	fi
    else
	# Tag the top commit with the tar name
	if [ x"$DRY_RUN" = x ]; then
	    git tag $GPGKEY -s -m $tag_name $tag_name
	    if [ $? -ne 0 ]; then
		echo "Error:  unable to tag module with \"$tag_name\"."
		cd $top_src
		return 1
	    else
		echo "Info: module tagged with \"$tag_name\"."
	    fi
	else
	    echo "Info: skipping the commit tagging in dry-run mode."
	fi
    fi

    # --------- Now the tarballs are ready to upload ----------

    # The hostname which is used to connect to the development resources
    hostname="annarchy.freedesktop.org"

    # Some hostnames are also used as /srv subdirs
    host_fdo="www.freedesktop.org"
    host_xorg="xorg.freedesktop.org"
    host_dri="dri.freedesktop.org"
    host_mesa="mesa.freedesktop.org"
    host_wayland="wayland.freedesktop.org"

    # Mailing lists where to post the all [Announce] e-mails
    list_to="xorg-announce@lists.x.org"

    # Mailing lists to be CC according to the project (xorg|dri|xkb)
    list_xorg_user="xorg@lists.x.org"
    list_dri_devel="dri-devel@lists.freedesktop.org"
    list_mesa_announce="mesa-announce@lists.freedesktop.org"
    list_mesa_devel="mesa-dev@lists.freedesktop.org"

    list_xkb="xkb@listserv.bat.ru"
    list_xcb="xcb@lists.freedesktop.org"
    list_nouveau="nouveau@lists.freedesktop.org"
    list_wayland="wayland-devel@lists.freedesktop.org"
    list_input="input-tools@lists.freedesktop.org"

    host_current=$host_xorg
    section_path=archive/individual/$section
    srv_path="/srv/$host_current/$section_path"
    list_cc=$list_xorg_user

    # Handle special cases such as non xorg projects or migrated xorg projects
    # Nouveau has its own list and section, but goes with the other drivers
    if [ x"$section" = xnouveau ]; then
        section_path=archive/individual/driver
        srv_path="/srv/$host_current/$section_path"
        list_cc=$list_nouveau
    fi

    # Xcb has a separate mailing list
    if [ x"$section" = xxcb ]; then
	list_cc=$list_xcb
    fi

    # Module mesa/drm goes in the dri "libdrm" section
    if [ x"$section" = xdrm ]; then
        host_current=$host_dri
        section_path=libdrm
        srv_path="/srv/$host_current/www/$section_path"
        list_cc=$list_dri_devel
    elif [ x"$section" = xmesa ]; then
        host_current=$host_mesa
        section_path=archive
        srv_path="/srv/$host_current/www/$section_path"
        list_to=$list_mesa_announce
        list_cc=$list_mesa_devel
    elif [ x"$section" = xdemos ] || [ x"$section" = xglu ]; then
        host_current=$host_mesa
        section_path=archive/$section
        srv_path="/srv/$host_current/www/$section_path"
        list_to=$list_mesa_announce
        list_cc=$list_mesa_devel
    fi

    # Module xkeyboard-config goes in a subdir of the xorg "data" section
    if [ x"$section" = xxkeyboard-config ]; then
	host_current=$host_xorg
	section_path=archive/individual/data/$section
	srv_path="/srv/$host_current/$section_path"
	list_cc=$list_xkb
    fi

    if [ x"$section" = xlibevdev ]; then
	host_current=$host_fdo
	section_path="software/$section"
	srv_path="/srv/$host_current/www/$section_path"
	list_to=$list_input
	unset list_cc
    fi

    if [ x"$section" = xwayland ] ||
       [ x"$section" = xweston ]; then
        host_current=$host_wayland
        section_path="releases"
        srv_path="/srv/$host_current/www/$section_path"
        list_to=$list_wayland
        unset list_cc
    elif [ x"$section" = xlibinput ]; then
        host_current=$host_fdo
        section_path="software/libinput"
        srv_path="/srv/$host_current/www/$section_path"
        list_to=$list_wayland
        unset list_cc
    elif [ x"$section" = xevemu ]; then
        host_current=$host_fdo
        section_path="software/evemu"
        srv_path="/srv/$host_current/www/$section_path"
        list_to=$list_input
        unset list_cc
    fi

    # Use personal web space on the host for unit testing (leave commented out)
    # srv_path="~/public_html$srv_path"

    # Check that the server path actually does exist
    echo "Info: checking if path exists on web server:"
    ssh $USER_NAME$hostname ls $srv_path >/dev/null 2>&1
    if [ $? -ne 0 ]; then
	echo "Error: the path \"$srv_path\" on the web server does not exist."
	cd $top_src
	return 1
    fi

    # Check for already existing tarballs
    for tarball in $targz $tarbz2 $tarxz; do
	echo "Info: checking if tarball $tarball already exists on web server:"
	ssh $USER_NAME$hostname ls $srv_path/$tarball  >/dev/null 2>&1
	if [ $? -eq 0 ]; then
	    if [ "x$FORCE" = "xyes" ]; then
		echo "Warning: overwriting released tarballs due to --force option."
	    else
		echo "Error: tarball $tar_name already exists. Use --force to overwrite."
		cd $top_src
		return 1
	    fi
	fi
    done

    # Upload to host using the 'scp' remote file copy program
    if [ x"$DRY_RUN" = x ]; then
	echo "Info: uploading tarballs to web server:"
	scp $targz $tarbz2 $tarxz $siggz $sigbz2 $sigxz $USER_NAME$hostname:$srv_path
	if [ $? -ne 0 ]; then
	    echo "Error: the tarballs uploading failed."
	    cd $top_src
	    return 1
	fi
    else
	echo "Info: skipping tarballs uploading in dry-run mode."
	echo "      \"$srv_path\"."
    fi

    # Pushing the top commit tag to the remote repository
    if [ x$DRY_RUN = x ]; then
	echo "Info: pushing tag \"$tag_name\" to remote \"$remote_name\":"
	git push $remote_name $tag_name
	if [ $? -ne 0 ]; then
	    echo "Error: unable to push tag \"$tag_name\" to the remote repository."
	    echo "       it is recommended you fix this manually and not run the script again"
	    cd $top_src
	    return 1
	fi
    else
	echo "Info: skipped pushing tag \"$tag_name\" to the remote repository in dry-run mode."
    fi

    SHA1SUM=`which sha1sum || which gsha1sum`
    SHA256SUM=`which sha256sum || which gsha256sum`
    SHA512SUM=`which sha512sum || which gsha512sum`

    # --------- Generate the announce e-mail ------------------
    # Failing to generate the announce is not considered a fatal error

    # Git-describe returns only "the most recent tag", it may not be the expected one
    # However, we only use it for the commit history which will be the same anyway.
    tag_previous=`git describe --abbrev=0 HEAD^ 2>/dev/null`
    # Git fails with rc=128 if no tags can be found prior to HEAD^
    if [ $? -ne 0 ]; then
	if [ $? -ne 0 ]; then
	    echo "Warning: unable to find a previous tag."
	    echo "         perhaps a first release on this branch."
	    echo "         Please check the commit history in the announce."
	fi
    fi
    if [ x"$tag_previous" != x ]; then
	# The top commit may not have been tagged in dry-run mode. Use commit.
	tag_range=$tag_previous..$local_top_commit_sha
    else
	tag_range=$tag_name
    fi
    pushd "$tar_root"
    generate_announce > "$tar_name.announce"
    popd

    echo "Info: [ANNOUNCE] template generated in \"$announce_dir/$tar_name.announce\" file."
    echo "      Please pgp sign and send it."

    # --------- Update the JH Build moduleset -----------------
    # Failing to update the jh moduleset is not considered a fatal error
    if [ x"$JH_MODULESET" != x ]; then
	for tarball in $targz $tarbz2 $tarxz; do
	    if [ x$DRY_RUN = x ]; then
		sha1sum=`$SHA1SUM $tarball | cut -d' ' -f1`
		$top_src/util/modular/update-moduleset.sh $JH_MODULESET $sha1sum $tarball
		echo "Info: updated jh moduleset: \"$JH_MODULESET\""
	    else
		echo "Info: skipping jh moduleset \"$JH_MODULESET\" update in dry-run mode."
	    fi

	    # $tar* may be unset, so simply loop through all of them and the
	    # first one that is set updates the module file
	    break
	done
    fi


    # --------- Successful completion --------------------------
    cd $top_src
    return 0

}

#------------------------------------------------------------------------------
#			Function: usage
#------------------------------------------------------------------------------
# Displays the script usage and exits successfully
#
usage() {
    basename="`expr "//$0" : '.*/\([^/]*\)'`"
    cat <<HELP

Usage: $basename [options] path...

Where "path" is a relative path to a git module, including '.'.

Options:
  --dist              make 'dist' instead of 'distcheck'; use with caution
  --distcheck         Default, ignored for compatibility
  --dry-run           Does everything except tagging and uploading tarballs
  --force             Force overwriting an existing release
  --gpgkey <key>      Specify the key used to sign the git tag/release tarballs
  --help              Display this help and exit successfully
  --modfile <file>    Release the git modules specified in <file>
  --moduleset <file>  The jhbuild moduleset full pathname to be updated
  --no-quit           Do not quit after error; just print error message
  --user <name>@      Username of your fdo account if not configured in ssh

Environment variables defined by the "make" program and used by release.sh:
  MAKE        The name of the make command [make]
  MAKEFLAGS:  Options to pass to all \$(MAKE) invocations

HELP
}

#------------------------------------------------------------------------------
#			Script main line
#------------------------------------------------------------------------------
#

# Choose which make program to use (could be gmake)
MAKE=${MAKE:="make"}

# Choose which grep program to use (on Solaris, must be gnu grep)
if [ "x$GREP" = "x" ] ; then
    if [ -x /usr/gnu/bin/grep ] ; then
	GREP=/usr/gnu/bin/grep
    else
	GREP=grep
    fi
fi

# Find path for GnuPG v2
if [ "x$GPG" = "x" ] ; then
    if [ -x /usr/bin/gpg2 ] ; then
	GPG=/usr/bin/gpg2
    else
	GPG=gpg
    fi
fi

# Avoid problems if GPGKEY is already set in the environment
unset GPGKEY

# Set the default make tarball creation command
MAKE_DIST_CMD=distcheck

# Process command line args
while [ $# != 0 ]
do
    case $1 in
    # Use 'dist' rather than 'distcheck' to create tarballs
    # You really only want to do this if you're releasing a module you can't
    # possibly build-test.  Please consider carefully the wisdom of doing so.
    --dist)
	MAKE_DIST_CMD=dist
	;;
    # Use 'distcheck' to create tarballs
    --distcheck)
	MAKE_DIST_CMD=distcheck
	;;
    # Does everything except uploading tarball
    --dry-run)
	DRY_RUN=yes
	;;
    # Force overwriting an existing release
    # Use only if nothing changed in the git repo
    --force)
	FORCE=yes
	;;
    # Allow user specified GPG key
    --gpgkey)
	check_option_args $1 $2
	shift
	check_gpgkey $1
	GPGKEY="-u $1"
	;;
    # Display this help and exit successfully
    --help)
	usage
	exit 0
	;;
    # Release the git modules specified in <file>
    --modfile)
	check_option_args $1 $2
	shift
	MODFILE=$1
	;;
    # The jhbuild moduleset to update with relase info
    --moduleset)
	check_option_args $1 $2
	shift
	JH_MODULESET=$1
	;;
    # Do not quit after error; just print error message
    --no-quit)
	NO_QUIT=yes
	;;
    # Username of your fdo account if not configured in ssh
    --user)
	check_option_args $1 $2
	shift
	USER_NAME=$1
	;;
    --*)
	echo ""
	echo "Error: unknown option: $1"
	echo ""
	usage
	exit 1
	;;
    -*)
	echo ""
	echo "Error: unknown option: $1"
	echo ""
	usage
	exit 1
	;;
    *)
	if [ x"${MODFILE}" != x ]; then
	    echo ""
	    echo "Error: specifying both modules and --modfile is not permitted"
	    echo ""
	    usage
	    exit 1
	fi
	INPUT_MODULES="${INPUT_MODULES} $1"
	;;
    esac

    shift
done

umask=$(umask)
if [ "${umask}" != "022" -o "${umask}" != "0022" ]; then
    echo ""
    echo "Error: umask is not 022"
    echo ""
    exit 1
fi

# If no modules specified (blank cmd line) display help
check_modules_specification

# Read the module file and normalize input in INPUT_MODULES
read_modfile

# Loop through each module to release
# Exit on error if --no-quit no specified
process_modules

# Print the epilog with final status
print_epilog
