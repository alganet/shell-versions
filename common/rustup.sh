shvr_download_rustup ()
{
	if ! test -f "${SHVR_DIR_SRC}/rustup-init-1.28.2.sh"
	then
		shvr_fetch "https://raw.githubusercontent.com/rust-lang/rustup/refs/tags/1.28.2/rustup-init.sh" "${SHVR_DIR_SRC}/rustup-init-1.28.2.sh"
	fi
}