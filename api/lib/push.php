<?php
declare(strict_types=1);

/**
 * OneSignal broadcast. Every caller treats this as fire-and-forget: a slow or
 * dead push service must never fail the admin action that triggered it.
 */

/** True kapag may credentials at nasa production host tayo. */
function push_enabled(): bool
{
    if (ONESIGNAL_APP_ID === '' || ONESIGNAL_REST_KEY === '') return false;
    $host = explode(':', $_SERVER['HTTP_HOST'] ?? '')[0];
    return $host === PUSH_HOST;
}

/** Send one notification to every subscribed device. False = not sent. */
function push_send(string $title, string $body): bool
{
    if (!push_enabled()) {
        error_log('push skipped: host/key');
        return false;
    }

    $payload = json_encode_body([
        'app_id'             => ONESIGNAL_APP_ID,
        'included_segments'  => ['Subscribed Users'],
        'headings'           => ['en' => $title],
        'contents'           => ['en' => $body],
    ]);

    $ch = curl_init('https://api.onesignal.com/notifications');
    curl_setopt_array($ch, [
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => $payload,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 5,
        CURLOPT_HTTPHEADER     => [
            'Authorization: Key ' . ONESIGNAL_REST_KEY,
            'Content-Type: application/json',
        ],
    ]);

    $out = curl_exec($ch);
    $status = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $error = curl_error($ch);
    curl_close($ch);

    if ($out === false || $status < 200 || $status >= 300) {
        error_log('push failed: ' . ($error !== '' ? $error : 'HTTP ' . $status . ' ' . substr((string) $out, 0, 300)));
        return false;
    }
    return true;
}
