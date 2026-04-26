# Installed to /etc/profile.d/jog-remind.sh — reminds operator to run the wizard once.
if [[ -n "${PS1:-}" ]] && [[ "$(id -u)" -ne 0 ]] && [[ ! -f /etc/jog/wizard.done ]]; then
  echo ""
  echo "  [JOG] First-time setup: run  sudo jog-install-wizard"
  echo ""
fi
