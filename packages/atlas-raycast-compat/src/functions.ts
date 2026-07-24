import { CompatibilityError } from "./errors.js";
export {
  Cache, Clipboard, LocalStorage, closeMainWindow, confirmAlert, getPreferenceValues,
  launchCommand, showHUD, showToast,
} from "@atlas/api";
export function openExtensionPreferences(): never {
  throw new CompatibilityError("openExtensionPreferences", "Atlas settings deep link");
}
export const AI = new Proxy({}, { get() { throw new CompatibilityError("AI"); } });
