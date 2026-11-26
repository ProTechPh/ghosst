<?php
require_once __DIR__ . '/../includes/db_config.php';
require_once __DIR__ . '/includes/layout.php';
require_once __DIR__ . '/includes/error_handler.php';

$admin = requireSocialModerator();
$pdo = getPDO();
$csrf = csrfToken();
$flashMsg = '';
$flashType = 'success';

/**
 * Pinapayagan ang aliases (hal. `resolved` -> `reviewed`) para hindi mag-error
 * ang matatandang report rows. Alaways may malinaw na mensahe kung may mali.
 */
$statusAliases = [
    'reel_status'    => ['visible' => 'visible', 'hidden' => 'hidden', 'deleted' => 'deleted'],
    'comment_status' => ['visible' => 'visible', 'hidden' => 'hidden', 'deleted' => 'deleted'],
    'report_status'  => ['reviewed' => 'reviewed', 'resolved' => 'reviewed', 'dismissed' => 'dismissed', 'open' => 'open'],
];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!verifyCsrf($_POST['csrf_token'] ?? '')) {
        $flashMsg = 'Invalid CSRF token.';
        $flashType = 'error';
    } else {
        try {
            $action = trim((string) ($_POST['action'] ?? ''));
            $id = trim((string) ($_POST['id'] ?? ''));
            $rawStatus = trim((string) ($_POST['status'] ?? ''));
            if (!isset($statusAliases[$action])) throw new Exception('Unknown action.');
            $status = $statusAliases[$action][$rawStatus] ?? null;
            if ($status === null) {
                $choices = implode(', ', array_keys($statusAliases[$action]));
                throw new Exception("Unsupported status '$rawStatus'. Choose: $choices.");
            }
            if ($id === '' || strlen($id) > 64) throw new Exception('Invalid target.');
            if ($action === 'reel_status') {
                $exists = $pdo->prepare('SELECT id FROM app_reels WHERE id = ?');
                $exists->execute([$id]);
                if (!$exists->fetchColumn()) throw new Exception('Reel not found.');
                $pdo->prepare('UPDATE app_reels SET status = ?, updated_at = UTC_TIMESTAMP() WHERE id = ?')->execute([$status, $id]);
            } elseif ($action === 'comment_status') {
                $row = $pdo->prepare('SELECT reel_id FROM app_reel_comments WHERE id = ?');
                $row->execute([$id]);
                if (!$row->fetchColumn()) throw new Exception('Comment not found.');
                $pdo->prepare('UPDATE app_reel_comments SET status = ? WHERE id = ?')->execute([$status, $id]);
            } else {
                $exists = $pdo->prepare('SELECT id FROM app_reports WHERE id = ?');
                $exists->execute([$id]);
                if (!$exists->fetchColumn()) throw new Exception('Report not found.');
                $pdo->prepare('UPDATE app_reports SET status = ? WHERE id = ?')->execute([$status, $id]);
            }
            logAdminAction($pdo, $admin, $action, "$action $id -> $status");
            $flashMsg = 'Status updated.';
        } catch (Exception $e) {
            $flashMsg = $e->getMessage();
            $flashType = 'error';
        }
    }
}

$statusFilter = (string) ($_GET['status'] ?? '');
$where = in_array($statusFilter, ['pending', 'visible', 'hidden', 'deleted'], true) ? 'WHERE r.status = ?' : '';
$params = $where !== '' ? [$statusFilter] : [];
$reels = $pdo->prepare("SELECT r.id, r.caption, r.poster_url, r.status, r.created_at, u.username,
    (SELECT COUNT(*) FROM app_reel_media m WHERE m.reel_id = r.id AND m.status = 'visible') AS image_count
  FROM app_reels r JOIN users u ON u.id = r.user_id $where ORDER BY r.created_at DESC LIMIT 100");
$reels->execute($params);
$reels = $reels->fetchAll(PDO::FETCH_ASSOC);
$reports = $pdo->query("SELECT id, target_type, target_id, reason, details, content_snapshot, status, created_at
  FROM app_reports ORDER BY (status = 'open') DESC, created_at DESC LIMIT 100")->fetchAll(PDO::FETCH_ASSOC);
$comments = $pdo->query("SELECT c.id, c.text, c.status, c.created_at, r.id AS reel_id, r.caption AS reel_caption
  FROM app_reel_comments c JOIN app_reels r ON r.id = c.reel_id ORDER BY c.created_at DESC LIMIT 100")->fetchAll(PDO::FETCH_ASSOC);

$visibleCount = count(array_filter($reels, fn ($r) => $r['status'] === 'visible'));
$hiddenCount = count(array_filter($reels, fn ($r) => $r['status'] === 'hidden'));
$openReports = count(array_filter($reports, fn ($r) => $r['status'] === 'open'));

renderAdminHead('Reels & Reports');
renderAdminHeader($admin);
renderAdminSidebar($admin, 'reels');
?>
<style>
  .gs-feed-head{display:flex;flex-wrap:wrap;gap:1rem;align-items:center;justify-content:space-between;margin:1rem 0 1.25rem}
  .gs-filter{display:flex;gap:.5rem;align-items:center;flex-wrap:wrap}
  .gs-filter select{min-width:130px}
  .gs-pill{display:inline-flex;align-items:center;gap:.35rem;padding:.25rem .65rem;border-radius:999px;font-size:.72rem;font-weight:600;letter-spacing:.02em}
  .gs-pill-visible{color:#22d3ee;background:rgba(34,211,238,.12);border:1px solid rgba(34,211,238,.28)}
  .gs-pill-hidden{color:#fbbf24;background:rgba(251,191,36,.12);border:1px solid rgba(251,191,36,.28)}
  .gs-pill-deleted,.gs-pill-open{color:#f87171;background:rgba(248,113,113,.12);border:1px solid rgba(248,113,113,.28)}
  .gs-pill-reviewed{color:#34d399;background:rgba(52,211,153,.12);border:1px solid rgba(52,211,153,.28)}
  .gs-pill-dismissed{color:#94a3b8;background:rgba(148,163,184,.12);border:1px solid rgba(148,163,184,.28)}
  .gs-pending{color:#94a3b8;background:rgba(148,163,184,.12);border:1px solid rgba(148,163,184,.28)}
  .gs-reel-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:1rem}
  .gs-reel-card{border:1px solid rgba(255,255,255,.08);border-radius:16px;background:rgba(255,255,255,.025);overflow:hidden}
  .gs-reel-media{position:relative;width:100%;aspect-ratio:4/5;background:#05070a;display:flex;align-items:center;justify-content:center;overflow:hidden}
  .gs-reel-media img{width:100%;height:100%;object-fit:contain}
  .gs-reel-media .gs-empty{color:#64748b;font-size:.8rem}
  .gs-reel-body{padding:.9rem 1rem 1rem}
  .gs-reel-title{font-weight:700;font-size:.95rem;margin-bottom:.35rem;line-height:1.35;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
  .gs-reel-meta{color:var(--text-lo);font-size:.75rem;margin-bottom:.75rem}
  .gs-row{display:flex;gap:.5rem;align-items:center;flex-wrap:wrap}
  .gs-row form{display:flex;gap:.5rem;align-items:center;flex-wrap:wrap}
  .gs-section-title{display:flex;align-items:center;gap:.6rem;margin:2rem 0 .9rem;font-size:1.05rem;font-weight:700}
  .gs-section-title .gs-count{font-family:var(--ff-mono);font-size:.7rem;color:var(--text-lo);font-weight:400}
  .gs-report{border:1px solid rgba(255,255,255,.08);border-left:3px solid rgba(248,113,113,.6);border-radius:12px;background:rgba(255,255,255,.025);padding:.9rem 1rem;margin-bottom:.75rem}
  .gs-report-head{display:flex;gap:.6rem;align-items:center;flex-wrap:wrap;margin-bottom:.5rem}
  .gs-snapshot{border-radius:8px;background:rgba(0,0,0,.25);padding:.6rem .8rem;font-size:.8rem;line-height:1.5;margin:.5rem 0;max-height:110px;overflow:auto}
  .gs-report-details{color:var(--text-lo);font-size:.8rem;margin-bottom:.75rem}
  .gs-comment{border:1px solid rgba(255,255,255,.07);border-radius:10px;padding:.75rem .9rem;margin-bottom:.6rem;background:rgba(255,255,255,.02)}
  .gs-comment-meta{color:var(--text-lo);font-size:.72rem;margin-bottom:.35rem}
  .gs-stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:.75rem;margin-bottom:1.25rem}
</style>
<main class="gs-main"><div class="gs-content">
  <?php renderPageHeader('Reels & Reports', 'camera-reels-fill', 'Moderate public videos, comments and reports'); ?>
  <?php renderFlashMessage($flashMsg, $flashType); ?>

  <div class="gs-stats">
    <?php renderStatCard((string) count($reels), 'Reels shown', 'camera-reels-fill', 'teal'); ?>
    <?php renderStatCard((string) $visibleCount, 'Visible', 'eye-fill', 'green'); ?>
    <?php renderStatCard((string) $hiddenCount, 'Hidden', 'eye-slash-fill', 'gold'); ?>
    <?php renderStatCard((string) $openReports, 'Open reports', 'flag-fill', 'red'); ?>
  </div>

  <div class="gs-feed-head">
    <form method="get" class="gs-filter">
      <label for="status-filter">Status</label>
      <select id="status-filter" name="status">
        <option value="">All</option>
        <?php foreach (['pending', 'visible', 'hidden', 'deleted'] as $option): ?>
          <option value="<?= $option ?>" <?= $statusFilter === $option ? 'selected' : '' ?>><?= ucfirst($option) ?></option>
        <?php endforeach; ?>
      </select>
      <button class="btn-outline btn-sm" type="submit">Filter</button>
    </form>
  </div>

  <div class="gs-section-title"><i class="bi bi-images"></i> Reels <span class="gs-count"><?= count($reels) ?></span></div>
  <?php if (!$reels): ?>
    <p style="color:var(--text-lo)">No reels for this filter.</p>
  <?php endif; ?>
  <div class="gs-reel-grid">
    <?php foreach ($reels as $reel): ?>
      <article class="gs-reel-card">
        <div class="gs-reel-media">
          <?php if (!empty($reel['poster_url'])): ?>
            <img src="<?= htmlspecialchars((string) $reel['poster_url']) ?>" alt="Reel preview" loading="lazy">
          <?php else: ?><span class="gs-empty"><i class="bi bi-image"></i> No preview</span><?php endif; ?>
        </div>
        <div class="gs-reel-body">
          <div class="gs-reel-title"><?= htmlspecialchars($reel['caption'] !== '' ? $reel['caption'] : '(no caption)') ?></div>
          <div class="gs-reel-meta">
            @<?= htmlspecialchars($reel['username']) ?> ·
            <span class="gs-pill gs-pill-<?= htmlspecialchars($reel['status']) ?>"><?= htmlspecialchars(ucfirst($reel['status'])) ?></span> ·
            <?= htmlspecialchars($reel['created_at']) ?> ·
            <?= (int) ($reel['image_count'] ?? 0) ?> images
          </div>
          <form method="post" class="gs-row">
            <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($csrf) ?>">
            <input type="hidden" name="action" value="reel_status">
            <input type="hidden" name="id" value="<?= htmlspecialchars($reel['id']) ?>">
            <select name="status" aria-label="New status">
              <?php foreach (['visible', 'hidden', 'deleted'] as $option): ?>
                <option value="<?= $option ?>" <?= $reel['status'] === $option ? 'selected' : '' ?>><?= ucfirst($option) ?></option>
              <?php endforeach; ?>
            </select>
            <button class="btn-outline btn-sm" type="submit">Update</button>
          </form>
        </div>
      </article>
    <?php endforeach; ?>
  </div>

  <div class="gs-section-title"><i class="bi bi-flag-fill"></i> Reports <span class="gs-count"><?= count($reports) ?></span></div>
  <?php if (!$reports): ?><p style="color:var(--text-lo)">No reports yet.</p><?php endif; ?>
  <?php foreach ($reports as $report): ?>
    <article class="gs-report">
      <div class="gs-report-head">
        <span class="gs-pill gs-pill-<?= htmlspecialchars($report['status']) ?>"><?= htmlspecialchars(ucfirst($report['status'])) ?></span>
        <strong><?= htmlspecialchars($report['reason']) ?></strong>
        <span style="color:var(--text-lo);font-size:.75rem">
          <?= htmlspecialchars($report['target_type']) ?> #<?= htmlspecialchars($report['target_id']) ?> ·
          <?= htmlspecialchars($report['created_at']) ?>
        </span>
      </div>
      <?php if (!empty($report['content_snapshot'])): ?>
        <div class="gs-snapshot"><?= nl2br(htmlspecialchars((string) $report['content_snapshot'])) ?></div>
      <?php endif; ?>
      <?php if (!empty($report['details'])): ?>
        <div class="gs-report-details"><?= nl2br(htmlspecialchars((string) $report['details'])) ?></div>
      <?php endif; ?>
      <?php
      // Hiwalay na form bawat desisyon: ang admin.js ay nag-di-disable ng
      // submit button, kaya ang button name/value ay hindi lumalabas sa POST.
      foreach (['reviewed' => 'Reviewed', 'dismissed' => 'Dismiss', 'open' => 'Reopen'] as $decision => $label):
        if ($decision === 'open' && $report['status'] === 'open') continue;
      ?>
        <form method="post" class="gs-row" style="display:inline-flex;margin-right:.4rem">
          <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($csrf) ?>">
          <input type="hidden" name="action" value="report_status">
          <input type="hidden" name="id" value="<?= htmlspecialchars($report['id']) ?>">
          <input type="hidden" name="status" value="<?= $decision ?>">
          <button class="<?= $decision === 'dismissed' ? 'btn-danger btn-sm' : 'btn-outline btn-sm' ?>" type="submit">
            <i class="bi bi-<?= $decision === 'reviewed' ? 'check2-circle' : ($decision === 'dismissed' ? 'x-circle' : 'arrow-counterclockwise') ?>"></i>
            <?= $label ?>
          </button>
        </form>
      <?php endforeach; ?>
    </article>
  <?php endforeach; ?>

  <div class="gs-section-title"><i class="bi bi-chat-dots-fill"></i> Comments <span class="gs-count"><?= count($comments) ?></span></div>
  <?php if (!$comments): ?><p style="color:var(--text-lo)">No comments yet.</p><?php endif; ?>
  <?php foreach ($comments as $comment): ?>
    <div class="gs-comment">
      <div class="gs-comment-meta">
        on “<?= htmlspecialchars($comment['reel_caption']) ?>” ·
        <span class="gs-pill gs-pill-<?= htmlspecialchars($comment['status']) ?>"><?= htmlspecialchars(ucfirst($comment['status'])) ?></span> ·
        <?= htmlspecialchars($comment['created_at']) ?>
      </div>
      <div><?= nl2br(htmlspecialchars($comment['text'])) ?></div>
      <div class="gs-row" style="margin-top:.6rem">
        <?php foreach (['visible' => 'Show', 'hidden' => 'Hide', 'deleted' => 'Delete'] as $decision => $label): ?>
          <form method="post" class="gs-row" style="display:inline-flex">
            <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($csrf) ?>">
            <input type="hidden" name="action" value="comment_status">
            <input type="hidden" name="id" value="<?= htmlspecialchars($comment['id']) ?>">
            <input type="hidden" name="status" value="<?= $decision ?>">
            <button class="<?= $decision === 'deleted' ? 'btn-danger btn-sm' : 'btn-outline btn-sm' ?>" type="submit"><?= $label ?></button>
          </form>
        <?php endforeach; ?>
      </div>
    </div>
  <?php endforeach; ?>
</div></main>
<?php endAdminContent(); ?>
