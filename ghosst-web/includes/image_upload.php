<?php

function uploadProductImage(string $field, string $slug): ?string {
    return uploadImageTo($field, $slug, 'uploads/products', 'product');
}

function uploadCoverImage(string $field, string $slug): ?string {
    return uploadImageTo($field, $slug, 'uploads/covers', 'cover');
}

function uploadImageTo(string $field, string $slug, string $folder, string $prefix): ?string {
    if (empty($_FILES[$field]) || ($_FILES[$field]['error'] ?? UPLOAD_ERR_NO_FILE) === UPLOAD_ERR_NO_FILE) {
        return null;
    }

    if ($_FILES[$field]['error'] !== UPLOAD_ERR_OK) {
        throw new RuntimeException('Image upload failed.');
    }

    $tmp = $_FILES[$field]['tmp_name'];
    $info = getimagesize($tmp);
    if ($info === false) {
        throw new RuntimeException('Uploaded file must be an image.');
    }

    $allowed = [
        IMAGETYPE_JPEG => 'jpg',
        IMAGETYPE_PNG => 'png',
        IMAGETYPE_WEBP => 'webp',
    ];
    $type = $info[2] ?? 0;
    if (!isset($allowed[$type])) {
        throw new RuntimeException('Only JPG, PNG, and WEBP images are allowed.');
    }

    if (($_FILES[$field]['size'] ?? 0) > 5 * 1024 * 1024) {
        throw new RuntimeException('Image must be 5MB or smaller.');
    }

    $dir = __DIR__ . '/../' . $folder;
    if (!is_dir($dir)) {
        mkdir($dir, 0755, true);
    }

    $name = $prefix . '-' . date('YmdHis') . '-' . bin2hex(random_bytes(4)) . '.' . $allowed[$type];
    $dest = $dir . '/' . $name;
    if (!move_uploaded_file($tmp, $dest)) {
        throw new RuntimeException('Could not save uploaded image.');
    }

    return $folder . '/' . $name;
}

function deleteProductImageFile(?string $path): void {
    if (!$path || !str_starts_with($path, 'uploads/products/')) {
        return;
    }

    $full = realpath(__DIR__ . '/../' . $path);
    $base = realpath(__DIR__ . '/../uploads/products');
    if ($full && $base && str_starts_with($full, $base) && is_file($full)) {
        unlink($full);
    }
}
