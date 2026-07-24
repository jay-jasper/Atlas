export class CompatibilityError extends Error {
  constructor(readonly raycastSymbol: string, readonly atlasAlternative?: string) {
    super(atlasAlternative ? `${raycastSymbol} is unsupported; use ${atlasAlternative}` : `${raycastSymbol} is unsupported by Atlas`);
    this.name = "CompatibilityError";
  }
}
