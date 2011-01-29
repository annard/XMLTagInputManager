#! /bin/sh
#
# RunTextEditWithNewXMLTagInputManager <BuildProductsDir> ...
#
# Moves the existing XMLTagInputManager installation aside (searching in 
# ~/Library/InputManagers, /Network/Library/InputManagers, and 
# /Library/InputManagers in that order), symlinks back to the 
# <BuildProductsDir>, launches TextEdit, waits a bit, swaps the 
# old one back, and then waits for TextEdit to quit.
#
# Any arguments beyond the second one are just passed along to TextEdit.
#
# You can use it as a custom executable, but only for running, not debugging.
set -x
if [ $# -lt 1 ] ; then
    echo "usage $0 <BuildProductsDir> ..."
    exit 1
fi

BUILD_DIR=$1
shift

if [ \! -d "${BUILD_DIR}/XMLTagInputManager.bundle" -o \! -f "${BUILD_DIR}/Info" ] ; then 
    echo "There's no XMLTagInputManager to link to in ${BUILD_DIR}"
    exit 1
fi

INSTALL_DIR=${HOME}/Library/InputManagers
if [ \! -d "${INSTALL_DIR}/XMLTagInputManager" -o \! -f "${INSTALL_DIR}/XMLTagInputManager/Info" ] ; then 
    INSTALL_DIR=/Network/Library/InputManagers
    if [ \! -d "${INSTALL_DIR}/XMLTagInputManager" -o \! -f "${INSTALL_DIR}/XMLTagInputManager/Info" ] ; then 
        INSTALL_DIR=/Library/InputManagers
        if [ \! -d "${INSTALL_DIR}/XMLTagInputManager" -o \! -f "${INSTALL_DIR}/XMLTagInputManager/Info" ] ; then 
            echo "Cannot find an installed XMLTagInputManager."
            exit 1
        fi
    fi
fi

# Move aside the real one
cd "${INSTALL_DIR}"
mv XMLTagInputManager/Info XMLTagInputManager/Info.%%aside%%
mv XMLTagInputManager XMLTagInputManager.%%aside%%

# Link to the BUILD_DIR
ln -s "${BUILD_DIR}" XMLTagInputManager

# Run TextEdit
/Applications/TextEdit.app/Contents/MacOS/TextEdit $* &

# Wait
sleep 5

# Restore everything
cd "${INSTALL_DIR}"
rm XMLTagInputManager
mv XMLTagInputManager.%%aside%% XMLTagInputManager
mv XMLTagInputManager/Info.%%aside%% XMLTagInputManager/Info

# This seems not to really exit until TextEdit does, which is just what we want.
exit 0
 