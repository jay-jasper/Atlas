import { host } from "./host.js";
export interface Environment { commandName: string; extensionName: string; assetsPath: string; supportPath: string; isDevelopment: boolean; launchType: string }
let current: Environment = { commandName: "", extensionName: "", assetsPath: "", supportPath: "", isDevelopment: false, launchType: "userInitiated" };
export function installEnvironment(environment: Environment) { current = Object.freeze({ ...environment }); }
export const environment = new Proxy({} as Environment, { get: (_target, key) => current[key as keyof Environment] });
export const getPreferenceValues = <T extends object>() => host.request<T>("preferences.read", {});
