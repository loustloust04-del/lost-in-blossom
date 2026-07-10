// SMTP 发信 — 用「应用专用密码」，不走会过期的 OAuth。
// 用途：主动窥屏（peek_screen）时给用户 iCloud 邮箱发一封触发邮件，
// iOS「收到邮件」自动化随即截屏并上传 /api/peek。
// 配置全部来自 .env，缺任何一项都不发信（返回 configured:false）。
import nodemailer from 'nodemailer';

function cfg() {
  const host = process.env.SMTP_HOST || '';
  const port = Number(process.env.SMTP_PORT || 465);
  const user = process.env.SMTP_USER || '';
  const pass = process.env.SMTP_PASS || '';
  const from = process.env.SMTP_FROM || user;
  return { host, port, user, pass, from };
}

/// SMTP 是否已配好（host+user+pass 齐了才算）
export function mailerConfigured(): boolean {
  const c = cfg();
  return !!(c.host && c.user && c.pass);
}

let _tx: nodemailer.Transporter | null = null;
function transport() {
  if (_tx) return _tx;
  const c = cfg();
  _tx = nodemailer.createTransport({
    host: c.host,
    port: c.port,
    secure: c.port === 465, // 465=SSL，587=STARTTLS
    auth: { user: c.user, pass: c.pass },
  });
  return _tx;
}

/// 发一封邮件。失败抛错，调用方自己 catch。
export async function sendMail(to: string, subject: string, text: string): Promise<void> {
  if (!mailerConfigured()) throw new Error('SMTP 未配置（缺 SMTP_HOST/SMTP_USER/SMTP_PASS）');
  const c = cfg();
  await transport().sendMail({ from: c.from, to, subject, text });
}
