import { describe, expect, it } from "vitest";
import { isFeishuGroupChatId, resolveReceiveIdType } from "./targets.js";

describe("isFeishuGroupChatId", () => {
  it("returns true for oc_ prefix (group chat_id)", () => {
    expect(isFeishuGroupChatId("oc_123")).toBe(true);
    expect(isFeishuGroupChatId("oc_abc")).toBe(true);
    expect(isFeishuGroupChatId("OC_UpperCase")).toBe(true);
  });

  it("returns false for user/open ids and empty", () => {
    expect(isFeishuGroupChatId("ou_123")).toBe(false);
    expect(isFeishuGroupChatId("on_123")).toBe(false);
    expect(isFeishuGroupChatId("")).toBe(false);
    expect(isFeishuGroupChatId("u_123")).toBe(false);
  });
});

describe("resolveReceiveIdType", () => {
  it("resolves chat IDs by oc_ prefix", () => {
    expect(resolveReceiveIdType("oc_123")).toBe("chat_id");
  });

  it("resolves open IDs by ou_ prefix", () => {
    expect(resolveReceiveIdType("ou_123")).toBe("open_id");
  });

  it("defaults unprefixed IDs to user_id", () => {
    expect(resolveReceiveIdType("u_123")).toBe("user_id");
  });
});
