import { describe, expect, it } from "vitest";
import { lanes } from "../src/page";
import type { Item } from "../src/snapshot";

const link = (title: string, aspect?: number): Item => ({
  kind: "link", url: "https://example.com", title, site: "", ...(aspect ? { thumb: "t", aspect } : {}),
});

describe("list page feed", () => {
  it("puts each item in the shorter column, like the app", () => {
    const entries = [link("tall", 0.5), link("wide", 2), link("a"), link("b"), { kind: "text", text: "hi" } as Item]
      .map((item, index) => ({ item, index }));
    const [left, right] = lanes(entries, 2).map((lane) => lane.map((entry) => entry.index));
    // The tall photo outweighs a wide photo, two short links and a short text together.
    expect(left).toEqual([0]);
    expect(right).toEqual([1, 2, 3, 4]);
  });

  it("keeps every item exactly once", () => {
    const entries = Array.from({ length: 5 }, (_, index) => ({ item: link(`${index}`), index }));
    expect(lanes(entries, 2).flat().map((e) => e.index).sort()).toEqual([0, 1, 2, 3, 4]);
  });
});
