#!/bin/bash

source kubedock_setup

# Stow
## Required for https://github.com/eclipse/che/issues/22412

# /home/user/ will be mounted to by a PVC if persistUserHome is enabled
mountpoint -q /home/user/; HOME_USER_MOUNTED=$?

# This file will be created after stowing, to guard from executing stow everytime the container is started
STOW_COMPLETE=/home/user/.stow_completed

if [ $HOME_USER_MOUNTED -eq 0 ] && [ ! -f $STOW_COMPLETE ]; then
    # There may be regular, non-symlink files in /home/user that match the
    # pathing of files in /home/tooling. Stow will error out when it tries to
    # stow on top of that. Instead, we can append to the current
    # /home/tooling/.stow-local-ignore file to ignore pre-existing,
    # non-symlinked files in /home/user that match those in /home/tooling before
    # we run stow.
    #
    # Create two text files containing a sorted path-based list of files in
    # /home/tooling and /home/user. Cut off "/home/user" and "/home/tooling" and
    # only get the sub-paths so we can do a proper comparison
    #
    # In the case of /home/user, we want regular file types and not symbolic
    # links. 
    find /home/user -type f -xtype f -print  | sort | sed 's|/home/user||g' > /tmp/user.txt
    find /home/tooling -print | sort | sed 's|/home/tooling||g' > /tmp/tooling.txt
    # We compare the two files, trying to find files that exist in /home/user
    # and /home/tooling. Being that the files that get flagged here are not
    # already synlinks, we will want to ignore them.
    IGNORE_FILES="$(comm -12 /tmp/user.txt /tmp/tooling.txt)"
    # We no longer require the file lists, so remove them
    rm /tmp/user.txt /tmp/tooling.txt
    # For each file we need to ignore, append them to
    # /home/tooling/.stow-local-ignore.
    for f in $IGNORE_FILES; do echo "${f}" >> /home/tooling/.stow-local-ignore;done
    # We are now ready to run stow
    #
    # Create symbolic links from /home/tooling/ -> /home/user/
    stow . -t /home/user/ -d /home/tooling/ --no-folding -v 2 > /tmp/stow.log 2>&1
    # Vim does not permit .viminfo to be a symbolic link for security reasons, so manually copy it
    cp /home/tooling/.viminfo /home/user/.viminfo
    # We have to restore bash-related files back onto /home/user/ (since they will have been overwritten by the PVC)
    # but we don't want them to be symbolic links (so that they persist on the PVC)
    cp /home/tooling/.bashrc /home/user/.bashrc
    cp /home/tooling/.bash_profile /home/user/.bash_profile
    touch $STOW_COMPLETE
fi

exec "$@"
