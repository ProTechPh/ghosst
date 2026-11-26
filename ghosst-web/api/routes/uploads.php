<?php
declare(strict_types=1);

require_once __DIR__ . '/../../includes/image_upload.php';

/** Admin product images go to the site's FTP storage (uploads/products). */
function uploads_product_image(array $ctx): array
{
    require_admin($ctx);
    $file = $_FILES['image'] ?? null;
    if (!is_array($file) || ($file['error'] ?? UPLOAD_ERR_NO_FILE) === UPLOAD_ERR_NO_FILE) {
        throw new ApiError(400, 'image_required', 'Choose an image first.');
    }
    try {
        $path = uploadProductImage('image', 'product');
    } catch (RuntimeException $e) {
        throw new ApiError(400, 'invalid_image', $e->getMessage());
    }
    if ($path === null) {
        throw new ApiError(400, 'image_required', 'Choose an image first.');
    }
    return ['ok' => true, 'path' => $path];
}

/**
 * R2 presign ay hindi pa naka-port sa PHP. Hindi ito ginagamit ng app.
 * Pareho ang error code sa Worker kapag walang storage.
 */
function uploads_presign(array $ctx): array
{
    require_admin($ctx);
    throw new ApiError(503, 'storage_not_configured', 'Uploads are off — R2 is not set up yet');
}

function uploads_complete(array $ctx): array
{
    require_admin($ctx);
    throw new ApiError(503, 'storage_not_configured', 'Uploads are off — R2 is not set up yet');
}
