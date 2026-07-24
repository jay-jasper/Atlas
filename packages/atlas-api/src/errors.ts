export class AtlasApiError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly recovery?: string,
  ) {
    super(message);
    this.name = "AtlasApiError";
  }
}
