import { readFile } from "node:fs/promises";
import path from "node:path";
import { loadActiveCatalog, validateDraftBatch } from "./card-effect-draft-utils.mjs";

const args = process.argv.slice(2);
const inputIndex = args.findIndex((x) => x === "--input");
const inputPath = inputIndex >= 0 ? args[inputIndex + 1] : "supabase/seed/card_effect_review_batches/card-effect-review-20261029-attempt-01.json";
if (!inputPath || inputPath.startsWith("--")) {
  console.error("사용법: node scripts/validate-card-effect-drafts.mjs --input <draft-json>");
  process.exit(2);
}
const batch = JSON.parse(await readFile(path.resolve(inputPath), "utf8"));
const { facts } = await loadActiveCatalog();
const errors = validateDraftBatch(batch, facts);
const summary = { cardCount: batch.cards?.length ?? 0, candidateCount: 0, proposalCount: 0, dslValid: 0, dslInvalid: 0, pendingReview: 0, nativeRules: 0, errors };
for (const card of batch.cards ?? []) {
  for (const candidate of card.effectCandidates ?? []) {
    summary.candidateCount += 1;
    if (["native_existing_rule", "native_existing_cut_in", "native_general_partner_rules"].includes(candidate.draftStatus)) summary.nativeRules += 1;
    if (candidate.approvalStatus !== "approved") summary.pendingReview += 1;
    if (candidate.proposedDefinition) {
      summary.proposalCount += 1;
      if (candidate.structuralValidation?.status === "passed") summary.dslValid += 1;
      else summary.dslInvalid += 1;
    }
  }
}
console.log(JSON.stringify({
  result: errors.length || summary.dslInvalid ? "FAILED" : "PASSED_WITH_REVIEW_ITEMS",
  summary,
  note: "구조 검증 통과는 런타임 의미 검증이나 사람 승인이 아닙니다. 이 명령은 서버 카탈로그를 수정하지 않습니다."
}, null, 2));
if (errors.length || summary.dslInvalid > 0) process.exitCode = 1;
