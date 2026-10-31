import Foundation
public enum ModelNames {
    public enum PocketTTS {
        public static let condStep = "cond_step"
        /// Optional one-shot conditioning prefill. Fills the whole voice+text
        /// KV block in a single predict; when the file is absent the prefill
        /// runs token-by-token through `cond_step` (same output schema).
        public static let condPrefill = "cond_prefill"
        public static let flowlmStep = "flowlm_step"
        /// int8 variant of the FlowLM transformer published upstream alongside
        /// the default `flowlm_step`. Lives in the same `v2/<lang>/` directory
        /// and gets selected when the caller asks for `.int8` precision.
        public static let flowlmStepV2 = "flowlm_stepv2"
        public static let flowDecoder = "flow_decoder"
        /// v2.1 fused flow decoder (8-step LSD unrolled, 100% ANE). Replaces
        /// the per-step `flow_decoder` in v2.1 packs.
        public static let flowDecoderFused = "flow_decoder_fused"
        public static let mimiDecoder = "mimi_decoder"
        public static let mimiEncoder = "mimi_encoderv2"

        public static let condStepFile = condStep + ".mlmodelc"
        public static let condPrefillFile = condPrefill + ".mlmodelc"
        public static let flowlmStepFile = flowlmStep + ".mlmodelc"
        public static let flowlmStepV2File = flowlmStepV2 + ".mlmodelc"
        public static let flowDecoderFile = flowDecoder + ".mlmodelc"
        public static let flowDecoderFusedFile = flowDecoderFused + ".mlmodelc"
        public static let mimiDecoderFile = mimiDecoder + ".mlmodelc"
        public static let mimiEncoderFile = mimiEncoder + ".mlmodelc"

        /// Directory containing binary constants, tokenizer, and voice data.
        public static let constantsBinDir = "constants_bin"

        /// FlowLM filename for a given precision. Both variants ship in the
        /// same `v2/<lang>/` directory upstream; only the FlowLM transformer
        /// has an int8 variant — `cond_step`, `flow_decoder`, and
        /// `mimi_decoder` always load the default file.
        public static func flowlmStepFile(precision: PocketTtsPrecision) -> String {
            switch precision {
            case .fp16: return flowlmStepFile
            case .int8: return flowlmStepV2File
            }
        }

        /// Required files inside any language's `v2/<lang>/` pack for the
        /// given precision. The set differs only in the FlowLM filename.
        public static func requiredModels(precision: PocketTtsPrecision) -> Set<String> {
            [
                condPrefillFile,
                flowlmStepFile(precision: precision),
                flowDecoderFusedFile,
                mimiDecoderFile,
                constantsBinDir,
            ]
        }

        /// Required files for the default precision. Kept for callers that
        /// haven't been updated to pass a precision argument.
        public static let requiredModels: Set<String> = [
            condPrefillFile,
            flowlmStepFile,
            flowDecoderFusedFile,
            mimiDecoderFile,
            constantsBinDir,
        ]
    }
}
