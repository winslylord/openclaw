import { execFile, execFileSync } from "node:child_process";

const CP_TO_ENCODING: Record<string, string> = {
  "65001": "utf-8",
  "936": "gbk",
  "54936": "gb18030",
  "932": "shift-jis",
  "949": "euc-kr",
  "950": "big5",
  "874": "windows-874",
  "1250": "windows-1250",
  "1251": "windows-1251",
  "1252": "windows-1252",
  "1253": "windows-1253",
  "1254": "windows-1254",
  "1255": "windows-1255",
  "1256": "windows-1256",
  "1257": "windows-1257",
  "1258": "windows-1258",
};

let oemEncoding: string | undefined;

/**
 * Detect the console OEM code page via `chcp` so we can decode
 * schtasks output correctly on non-English Windows (e.g. GBK on Chinese).
 */
function resolveOemEncoding(): string {
  if (oemEncoding !== undefined) return oemEncoding;
  try {
    const out = execFileSync("cmd.exe", ["/c", "chcp"], {
      encoding: "utf8",
      windowsHide: true,
      timeout: 5_000,
    });
    const match = out.match(/:\s*(\d+)/);
    oemEncoding = (match && CP_TO_ENCODING[match[1]]) || "utf-8";
  } catch {
    oemEncoding = "utf-8";
  }
  return oemEncoding;
}

function decodeOutput(buf: Buffer): string {
  if (!buf.length) return "";
  const enc = resolveOemEncoding();
  if (enc === "utf-8") return buf.toString("utf8");
  try {
    return new TextDecoder(enc).decode(buf);
  } catch {
    return buf.toString("utf8");
  }
}

export async function execSchtasks(
  args: string[],
): Promise<{ stdout: string; stderr: string; code: number }> {
  return new Promise((resolve) => {
    execFile(
      "schtasks",
      args,
      { windowsHide: true, encoding: "buffer" },
      (error, stdoutBuf, stderrBuf) => {
        const stdout = decodeOutput(stdoutBuf);
        const stderr = decodeOutput(stderrBuf);
        if (!error) {
          resolve({ stdout, stderr, code: 0 });
          return;
        }
        const e = error as { code?: unknown; message?: unknown };
        resolve({
          stdout,
          stderr: stderr || (typeof e.message === "string" ? e.message : ""),
          code: typeof e.code === "number" ? e.code : 1,
        });
      },
    );
  });
}
