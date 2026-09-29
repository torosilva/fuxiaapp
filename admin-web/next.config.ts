import type { NextConfig } from "next";
import { assertEnvironment } from "./src/lib/env-guard";

// Refuse to build or start if a staging deployment points at production or carries server secrets.
assertEnvironment();

const nextConfig: NextConfig = {
  /* config options here */
};

export default nextConfig;
