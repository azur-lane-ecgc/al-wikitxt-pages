/**
 * Dump ecgc-dev CommonResourceData (TypeScript) to JSON for wiki generation.
 *
 * Usage (bun resolves the ecgc tsconfig `@/` alias, so run from the
 * ecgc frontend package directory):
 *
 *   cd <ecgc-dev>/packages/frontend
 *   bun run <wiki-repo>/scripts/common_resource/dump_common_resource.ts > common_resource.json
 *
 * Output: { "infinite": ResourceProps[], "finite": ResourceProps[] }
 * with totals precomputed by getTotalGuaranteed.
 */
import { InfiniteResourceData, FiniteResourceData } from "@/components/CommonResource/CommonResourceData/index"

const out = {
  infinite: InfiniteResourceData,
  finite: FiniteResourceData,
}

console.log(JSON.stringify(out, null, 2))
